--!strict
-- ci-gate playbook: watch a pull request's check rollup to a terminal
-- state and, while failing checks remain and a repair budget remains,
-- hand the failing run's logs to a configured agent for a repair push
-- committed with the configured signing arguments. The `watch`
-- operation returns a typed outcome — `green`, or `unresolved` carrying
-- the attempt count and a reason — rather than raising on exhaustion or
-- timeout, so the calling script owns the policy for a red run. The
-- playbook never asks a human: a red check is either agent-fixable or
-- environmental.
--
-- The playbook accepts no `cwd`: repair sessions run in the working
-- directory of the supplied `agent` handle, so a consumer running
-- outside a worktree pins the handle (e.g. std.agent.inDirectory)
-- before constructing the playbook.

local gh = require("../../std/gh")
local shell = require("../../std/shell")
local sessionConfig = require("../../std/session-config")

export type Outcome = {
	status: "green" | "unresolved",
	-- Repair pushes issued during this watch (0 when the rollup was
	-- green on the first poll).
	attempts: number,
	reason: string?,
}

export type Config = {
	-- Repair agent handle. Its sessions run in the handle's own working
	-- directory (the playbook sets no cwd).
	agent: Agent,
	-- Ordered session-config entries applied to every repair session.
	sessionConfig: { sessionConfig.Entry }?,
	-- Git commit-signing arguments applied to a repair commit (e.g.
	-- `{ "-S", "-s" }` for DCO sign-off), each passed as argv and
	-- shell-quoted; empty means commit without signing arguments.
	commitSignArgs: { string }?,
	-- How long one push's checks may run before the wait budget is
	-- exhausted (seconds, default 3600).
	timeoutSeconds: number?,
	-- Poll interval while checks settle (seconds, default 30).
	pollSeconds: number?,
	-- How many signed repair pushes a red rollup gets (default 3).
	repairAttempts: number?,
}

export type Instance = {
	-- Watch `prUrl`'s check rollup to a terminal state. Returns the
	-- typed outcome.
	watch: (self: Instance, prUrl: string) -> Outcome,
}

local DEFAULT_TIMEOUT_SECONDS = 3600
local DEFAULT_POLL_SECONDS = 30
local DEFAULT_REPAIR_ATTEMPTS = 3
-- A fetched log is truncated to this many characters before it enters a
-- repair prompt.
local LOG_EXCERPT_CAP = 8000

local PASS_CONCLUSIONS: { [string]: boolean } = {
	SUCCESS = true,
	NEUTRAL = true,
	SKIPPED = true,
}

local PENDING_STATUSES: { [string]: boolean } = {
	PENDING = true,
	QUEUED = true,
	IN_PROGRESS = true,
	WAITING = true,
	REQUESTED = true,
}

-- Classify one rollup entry. `gh`'s statusCheckRollup unions two shapes:
-- a CheckRun carries `status` + `conclusion`, and a StatusContext
-- carries `state`. Both are classified so a pending entry never reads
-- as a failure and a failing status context never reads as pending.
local function classify(entry: any): "pass" | "pending" | "fail"
	local state = entry.state
	if type(state) == "string" then
		if state == "SUCCESS" then
			return "pass"
		end
		if state == "PENDING" or state == "EXPECTED" then
			return "pending"
		end
		return "fail"
	end
	local conclusion = entry.conclusion
	if type(conclusion) == "string" and PASS_CONCLUSIONS[conclusion] then
		return "pass"
	end
	local status = entry.status
	if conclusion == nil or (type(status) == "string" and PENDING_STATUSES[status]) then
		return "pending"
	end
	return "fail"
end

local function parseRepo(prUrl: string): { owner: string, repo: string }?
	local owner, repo = string.match(prUrl, "^https?://github%.com/([^/]+)/([^/]+)/pull/%d+")
	if owner == nil or repo == nil then
		return nil
	end
	return { owner = owner, repo = repo }
end

local function entryLabel(entry: any): string
	local name = entry.name
	if type(name) == "string" and name ~= "" then
		return name
	end
	local context = entry.context
	if type(context) == "string" and context ~= "" then
		return context
	end
	return "(unnamed check)"
end

local function entryDetailsUrl(entry: any): string?
	local url = entry.detailsUrl
	if type(url) == "string" and url ~= "" then
		return url
	end
	local target = entry.targetUrl
	if type(target) == "string" and target ~= "" then
		return target
	end
	return nil
end

type Rollup = {
	failing: { any },
	pending: number,
}

local function readRollup(prUrl: string): Rollup
	local outcome = gh.run({ "pr", "view", prUrl, "--json", "statusCheckRollup" }, { json = true })
	if not outcome.ok then
		error(`ci-gate: could not read the check rollup for {prUrl}: {outcome.stderr}`)
	end
	local data = outcome.json :: { statusCheckRollup: { any }? }
	local entries: { any } = if data.statusCheckRollup ~= nil then data.statusCheckRollup else {}
	local failing: { any } = {}
	local pending = 0
	for _, entry in entries do
		local verdict = classify(entry)
		if verdict == "fail" then
			table.insert(failing, entry)
		elseif verdict == "pending" then
			pending += 1
		end
	end
	return { failing = failing, pending = pending }
end

-- Best-effort failed-log fetch for a check whose details URL names a
-- GitHub Actions run: `gh run view <id> --log-failed`. Any failure is
-- data (the entry's URL is still handed to the agent), never a raise.
local function fetchLog(repo: { owner: string, repo: string }?, entry: any): string?
	local url = entryDetailsUrl(entry)
	if url == nil then
		return nil
	end
	local runId = string.match(url, "/actions/runs/(%d+)")
	if runId == nil then
		return nil
	end
	local args: { string } = { "run", "view", runId, "--log-failed" }
	if repo ~= nil then
		table.insert(args, "--repo")
		table.insert(args, `{repo.owner}/{repo.repo}`)
	end
	local outcome = gh.run(args, {})
	if not outcome.ok then
		return nil
	end
	local text = outcome.stdout
	if #text > LOG_EXCERPT_CAP then
		text = string.sub(text, 1, LOG_EXCERPT_CAP) .. "\n… (log truncated)"
	end
	return text
end

-- The commit invocation the agent must use for the repair. Signing
-- arguments arrive as config data and are passed as argv (each
-- POSIX-quoted so a value with spaces or quotes survives the shell).
local function commitCommand(commitSignArgs: { string }): string
	if #commitSignArgs == 0 then
		return `git commit -m "<message>"`
	end
	local quoted: { string } = {}
	for _, arg in commitSignArgs do
		table.insert(quoted, shell.quote(arg))
	end
	return `git commit {table.concat(quoted, " ")} -m "<message>"`
end

local function buildRepairPrompt(
	prUrl: string,
	failing: { any },
	repo: { owner: string, repo: string }?,
	commitSignArgs: { string }
): string
	local lines: { string } = {
		`The CI checks on pull request {prUrl} are failing. Fix them in this working directory, then push the repair.`,
		"",
		"## Failing checks",
	}
	for _, entry in failing do
		local label = entryLabel(entry)
		local url = entryDetailsUrl(entry)
		local conclusion = entry.conclusion
		local state = entry.state
		local detail = if type(conclusion) == "string" and conclusion ~= "" then conclusion
			elseif type(state) == "string" and state ~= "" then state
			else "failed"
		local suffix = if url ~= nil then `: {url}` else ""
		table.insert(lines, `- {label} ({detail}){suffix}`)
		local log = fetchLog(repo, entry)
		if log ~= nil and log ~= "" then
			table.insert(lines, "")
			table.insert(lines, `### {label} log`)
			table.insert(lines, "```")
			table.insert(lines, log)
			table.insert(lines, "```")
		end
	end
	table.insert(lines, "")
	table.insert(
		lines,
		table.concat({
			"## Job",
			"1. Read the failing logs above (fetch any that are missing: `gh run view --log-failed` for workflow runs, or the job log behind each check's URL).",
			"2. Fix what they report in this working directory.",
			`3. Commit the fix with ${commitCommand(commitSignArgs)} and push to the pull request's branch.`,
			"",
			"If a failure cannot be fixed from here (infrastructure, secrets, a broken base branch), stop and say so instead of pushing.",
		}, "\n")
	)
	return table.concat(lines, "\n")
end

local M = {}

function M.new(config: Config): Instance
	local timeoutSeconds = if config.timeoutSeconds ~= nil then config.timeoutSeconds else DEFAULT_TIMEOUT_SECONDS
	local pollSeconds = if config.pollSeconds ~= nil then config.pollSeconds else DEFAULT_POLL_SECONDS
	local repairAttempts = if config.repairAttempts ~= nil then config.repairAttempts else DEFAULT_REPAIR_ATTEMPTS
	local commitSignArgs: { string } = if config.commitSignArgs ~= nil then config.commitSignArgs else {}

	local instance: Instance = {
		watch = function(_self: Instance, prUrl: string): Outcome
			local repo = parseRepo(prUrl)
			local deadline = os.time() + timeoutSeconds
			local attempts = 0
			while true do
				local rollup = readRollup(prUrl)
				if #rollup.failing == 0 and rollup.pending == 0 then
					return { status = "green", attempts = attempts, reason = nil }
				end
				if #rollup.failing > 0 then
					if attempts >= repairAttempts then
						return {
							status = "unresolved",
							attempts = attempts,
							reason = `PR checks are red and the {repairAttempts}-attempt repair budget is exhausted`,
						}
					end
					attempts += 1
					ptah.log(`ci-gate: {prUrl} checks red, repair attempt {attempts} of {repairAttempts}`)
					local session: Session = config.agent:session({ id = `ci-repair:{attempts}` })
					sessionConfig.apply(session, config.sessionConfig)
					local result = session:prompt(buildRepairPrompt(prUrl, rollup.failing, repo, commitSignArgs))
					ptah.log(`ci-gate: repair turn: {result.text}`)
					session:close()
					-- A repair push restarts the wait budget: the fresh run
					-- deserves its own full window to settle.
					deadline = os.time() + timeoutSeconds
				end
				if os.time() >= deadline then
					return {
						status = "unresolved",
						attempts = attempts,
						reason = `PR checks did not settle within the {timeoutSeconds}s wait budget`,
					}
				end
				ptah.sleep(pollSeconds * 1000)
			end
		end,
	}
	return instance
end

return M
