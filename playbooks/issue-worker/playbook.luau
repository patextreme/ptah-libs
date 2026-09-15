--!strict
-- issueWorker meta playbook: take one GitHub issue from pickup to a
-- reviewed, CI-green pull request by composing the stdlib, other
-- playbooks, and deterministic stages. One run processes at most one
-- issue and leaves nothing running between runs. See README.md in this
-- directory for the declared environment requirements.
--
-- The playbook owns the deterministic mechanics (worktree/branch
-- invariants, delivery re-checks, label lifecycle, bookkeeping) and
-- composes the openspec playbook (when enabled), the PR review loop,
-- and the CI gate. It never calls `ptah.agent` (agent handles arrive as
-- config), `ptah.ask`, or `ptah.exit`; every session — its own and the
-- nested playbooks' — runs in the per-issue worktree imposed once by
-- wrapping the configured handles with `std.agent.inDirectory`.

local gh = require("../../std/gh")
local shell = require("../../std/shell")
local stdAgent = require("../../std/agent")
local sessionConfig = require("../../std/session-config")
local openspecPlaybook = require("../openspec/playbook")
local prReviewLoop = require("../pr-review-loop/playbook")
local ciGatePlaybook = require("../ci-gate/playbook")
local git = require("./git")

export type Issue = {
	number: number,
	title: string,
	url: string,
	body: string,
}

-- The run outcome: outcomes as data, so the consumer's shim maps them
-- to exit codes. `issue` is nil only for `idle`; `prUrl` is set when a
-- pull request was opened; `reason` explains a `rejected` or `failed`
-- outcome.
export type Outcome = {
	status: "delivered" | "rejected" | "idle" | "failed",
	issue: Issue?,
	prUrl: string?,
	reason: string?,
}

export type Config = {
	-- Role handles. `agent` drives the playbook's own stages and is
	-- forwarded as the work handle to every nested playbook;
	-- `judgeAgent` reaches the nested openspec and PR-review-loop
	-- judges; `reporterAgent` reaches the nested PR review loop.
	agent: Agent,
	judgeAgent: Agent,
	reporterAgent: Agent,
	-- Ordered session-config arrays, following the library convention:
	-- `sessionConfig` drives the playbook's own stage sessions and is
	-- forwarded as the work config to every nested playbook,
	-- `judgeSessionConfig` reaches the nested judges, and
	-- `reporterSessionConfig` reaches the nested PR review loop.
	sessionConfig: { sessionConfig.Entry }?,
	judgeSessionConfig: { sessionConfig.Entry }?,
	reporterSessionConfig: { sessionConfig.Entry }?,
	-- Required repo shape. The library ships no default label, encoding
	-- no repository's label.
	readyLabel: string,
	blockedLabel: string,
	baseBranch: string,
	branchPrefix: string,
	-- Gate commands the delivery session runs before pushing.
	gateCommands: { string },
	-- Worktree directory, relative to the repository root by default
	-- (`"tmp"`). The consumer is responsible for gitignoring it.
	worktreeDir: string?,
	-- Conventional-commit vocabulary the triage verdict's commit type
	-- is drawn from.
	commitTypes: { string }?,
	-- Git commit-signing arguments applied to commits (e.g.
	-- `{ "-S", "-s" }`), each passed as argv and shell-quoted; also
	-- forwarded to the CI gate's repair commits.
	commitSignArgs: { string }?,
	-- Caps and CI bounds.
	pickupLimit: number?,
	maxAttempts: number?,
	reviewMaxIterations: number?,
	ciTimeoutSeconds: number?,
	ciPollSeconds: number?,
	ciRepairAttempts: number?,
	-- Opt-in openspec route. When false, triage offers only `direct`
	-- and `reject` and the run requires no openspec environment.
	openspec: boolean?,
	-- Repository prose injected into every playbook-authored stage
	-- prompt (triage, direct implementation, delivery).
	repoBrief: string?,
}

export type Instance = {
	-- Perform pickup and, when an issue is eligible, the whole
	-- lifecycle. Returns the outcome.
	run: (self: Instance) -> Outcome,
	-- Return the claimed issue, or nil when nothing is eligible.
	pickup: (self: Instance) -> Issue?,
	-- Run a claimed issue through to delivery or rejection.
	process: (self: Instance, issue: Issue) -> Outcome,
}

-- The resolved config: every optional field defaulted.
type Resolved = {
	agent: Agent,
	judgeAgent: Agent,
	reporterAgent: Agent,
	sessionConfig: { sessionConfig.Entry }?,
	judgeSessionConfig: { sessionConfig.Entry }?,
	reporterSessionConfig: { sessionConfig.Entry }?,
	readyLabel: string,
	blockedLabel: string,
	baseBranch: string,
	branchPrefix: string,
	gateCommands: { string },
	worktreeDir: string,
	commitTypes: { string },
	commitSignArgs: { string },
	pickupLimit: number,
	maxAttempts: number,
	reviewMaxIterations: number,
	ciTimeoutSeconds: number,
	ciPollSeconds: number,
	ciRepairAttempts: number,
	openspec: boolean,
	repoBrief: string?,
}

type Verdict = {
	route: string,
	rationale: string,
	commitType: string,
	changeName: string?,
}

type SubmittedVerdict = {
	route: string?,
	rationale: string?,
	commitType: string?,
	changeName: string?,
}

type ListedIssue = {
	number: number,
	title: string,
	url: string,
	createdAt: string,
	assignees: { { login: string } },
}

local DEFAULT_WORKTREE_DIR = "tmp"
local DEFAULT_COMMIT_TYPES = { "feat", "fix", "chore", "docs", "refactor", "test", "build", "ci", "perf", "revert" }
local DEFAULT_SIGN_ARGS: { string } = {}
local DEFAULT_PICKUP_LIMIT = 30
local DEFAULT_MAX_ATTEMPTS = 3
local DEFAULT_REVIEW_MAX_ITERATIONS = 5
local DEFAULT_CI_TIMEOUT_SECONDS = 3600
local DEFAULT_CI_POLL_SECONDS = 30
local DEFAULT_CI_REPAIR_ATTEMPTS = 3
-- Cosmetic label colors; labels themselves are config, colors are not.
local READY_LABEL_COLOR = "#5319E7"
local BLOCKED_LABEL_COLOR = "#D93F0B"

local DELIVERY_SCHEMA: { [string]: any } = {
	type = "object",
	additionalProperties = false,
	properties = { prUrl = { type = "string" } },
	required = { "prUrl" },
}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function parsePrUrl(prUrl: string): { owner: string, repo: string, number: string }?
	local owner, repo, number = string.match(prUrl, "^https?://github%.com/([^/]+)/([^/]+)/pull/(%d+)")
	if owner == nil or repo == nil or number == nil then
		return nil
	end
	return { owner = owner, repo = repo, number = number }
end

local function briefSuffix(cfg: Resolved): string
	if cfg.repoBrief == nil or cfg.repoBrief == "" then
		return ""
	end
	return `\n\nRepository brief:\n{cfg.repoBrief}`
end

-- The commit invocation a stage prompt tells the agent to use; signing
-- arguments arrive as config data and are passed as argv (each
-- POSIX-quoted so a value with spaces or quotes survives the shell).
local function commitInvocation(commitSignArgs: { string }): string
	if #commitSignArgs == 0 then
		return "git commit"
	end
	local quoted: { string } = {}
	for _, arg in commitSignArgs do
		table.insert(quoted, shell.quote(arg))
	end
	return "git commit " .. table.concat(quoted, " ")
end

-- ---------------------------------------------------------------------------
-- Bookkeeping (std.gh) — every GitHub write outside the PR
-- ---------------------------------------------------------------------------

local function ensureLabel(name: string, color: string): ()
	local outcome = gh.run({ "label", "create", name, "--color", color })
	if not outcome.ok and string.find(outcome.stderr, "already exists", 1, true) == nil then
		error(`issue-worker: gh label create {name} failed: {outcome.stderr}`, 0)
	end
end

local function ensureLabels(cfg: Resolved): ()
	ensureLabel(cfg.readyLabel, READY_LABEL_COLOR)
	ensureLabel(cfg.blockedLabel, BLOCKED_LABEL_COLOR)
end

local function issueComment(issueNumber: number, body: string): ()
	local outcome = gh.run({ "issue", "comment", tostring(issueNumber), "--body", body })
	if not outcome.ok then
		error(`issue-worker: gh issue comment on #{issueNumber} failed: {outcome.stderr}`, 0)
	end
end

local function markBlocked(cfg: Resolved, issueNumber: number, body: string): ()
	-- Release the claim and swap the labels: the issue is not ready for
	-- autonomous work until a human removes the blocked label and
	-- re-applies the ready one.
	gh.run({ "issue", "edit", tostring(issueNumber), "--remove-assignee", "@me" })
	gh.run({ "issue", "edit", tostring(issueNumber), "--remove-label", cfg.readyLabel })
	local add = gh.run({ "issue", "edit", tostring(issueNumber), "--add-label", cfg.blockedLabel })
	if not add.ok then
		error(`issue-worker: gh issue edit (add {cfg.blockedLabel}) on #{issueNumber} failed: {add.stderr}`, 0)
	end
	issueComment(issueNumber, body)
end

local function markRejected(cfg: Resolved, issueNumber: number, rationale: string): ()
	local quoted = "> " .. (rationale:gsub("\n", "\n> "))
	markBlocked(
		cfg,
		issueNumber,
		table.concat({
			"issueWorker triage rejected this issue as not actionable without human input.",
			"",
			quoted,
			"",
			(`Remove the {cfg.blockedLabel} label once the missing detail or decision is recorded, then re-apply {cfg.readyLabel} to hand it back.`),
		}, "\n")
	)
end

local function markFailed(cfg: Resolved, issueNumber: number, message: string): ()
	markBlocked(
		cfg,
		issueNumber,
		table.concat({
			"issueWorker claimed this issue but the run failed.",
			"",
			"```",
			message,
			"```",
		}, "\n")
	)
end

local function commentDelivered(issueNumber: number, prUrl: string): ()
	issueComment(issueNumber, `issueWorker delivered this issue: {prUrl} (review loop converged, CI checks green).`)
end

-- Failure bookkeeping must never propagate: the playbook's contract is
-- to return a failed outcome even when recording it also fails.
local function recordFailure(cfg: Resolved, issueNumber: number, message: string): ()
	local ok = pcall(markFailed, cfg, issueNumber, message)
	if not ok then
		ptah.log(`issue-worker: could not record the failure on #{issueNumber}`)
	end
end

-- ---------------------------------------------------------------------------
-- Pickup
-- ---------------------------------------------------------------------------

local function openPrExists(branch: string): boolean
	local outcome = gh.run({ "pr", "list", "--head", branch, "--state", "open", "--json", "number" }, { json = true })
	if not outcome.ok then
		error(`issue-worker: gh pr list failed: {outcome.stderr}`, 0)
	end
	local prs = outcome.json :: { { number: number } }
	return #prs > 0
end

local function branchExists(repoRoot: string, branch: string): boolean
	return shell.succeeds(("git -C %s show-ref --verify --quiet refs/heads/%s"):format(shell.quote(repoRoot), shell.quote(branch)))
end

-- The authenticated user's login, used to verify a claim after the
-- assignee write (the write itself cannot prove exclusivity).
local function authenticatedLogin(): string
	local outcome = gh.run({ "api", "user", "--jq", ".login" })
	if not outcome.ok then
		error(`issue-worker: could not resolve the authenticated user: {outcome.stderr}`, 0)
	end
	return outcome.stdout
end

-- Claim by assigning the authenticated user, then compare-and-swap:
-- GitHub's assignee write allows multiple assignees and succeeds even
-- when another run has already assigned itself, so winning is decided by
-- re-reading the assignee set. Anything other than exactly the
-- authenticated user is a lost claim: release our own assignment and
-- report the issue unclaimed.
-- The comparison-and-swap read, defensively: `gh.run` raises when a
-- zero-exit command returns unparseable JSON, and that raise would land
-- *after* our assignment. Any failure to read the assignee set means
-- winning cannot be proven, so it is reported as a lost claim.
local function readAssignees(issueNumber: number): { { login: string } }?
	local ok, viewed = pcall(function(): gh.GhOutcome
		return gh.run({ "issue", "view", tostring(issueNumber), "--json", "assignees" }, { json = true })
	end)
	if not ok or not viewed.ok then
		return nil
	end
	local data = viewed.json :: { assignees: { { login: string } }? }
	return data.assignees
end

local function claim(issueNumber: number, login: string): boolean
	local added = gh.run({ "issue", "edit", tostring(issueNumber), "--add-assignee", "@me" })
	if not added.ok then
		return false
	end
	local assignees = readAssignees(issueNumber)
	if assignees == nil or #assignees ~= 1 or assignees[1].login ~= login then
		-- The comparison-and-swap read failed or showed another claim, so
		-- winning cannot be proven; release our own assignment rather than
		-- leaving the issue claimed (which would make it permanently
		-- ineligible).
		gh.run({ "issue", "edit", tostring(issueNumber), "--remove-assignee", "@me" })
		return false
	end
	return true
end

local function pickupImpl(cfg: Resolved): Issue?
	ensureLabels(cfg)
	local login = authenticatedLogin()
	local outcome = gh.run({
		"issue",
		"list",
		"--label",
		cfg.readyLabel,
		"--state",
		"open",
		"--limit",
		tostring(cfg.pickupLimit),
		-- gh lists newest-first by default; ask for oldest-first so the
		-- limit bounds the oldest candidates (the client-side sort below
		-- stays as a safety net).
		"--search",
		"sort:created-asc",
		"--json",
		"number,title,url,createdAt,assignees",
	}, { json = true })
	if not outcome.ok then
		error(`issue-worker: gh issue list failed: {outcome.stderr}`, 0)
	end

	local listed = outcome.json :: { ListedIssue }
	table.sort(listed, function(a: ListedIssue, b: ListedIssue): boolean
		return a.createdAt < b.createdAt
	end)

	for _, candidate in ipairs(listed) do
		local branch = `{cfg.branchPrefix}{candidate.number}`
		local worktreePath = git.path(git.repoRoot(), cfg.worktreeDir, branch)
		if openPrExists(branch) then
			ptah.log(`issue-worker: #{candidate.number}: an open PR on {branch} exists already, skipping`)
		elseif #candidate.assignees > 0 then
			ptah.log(`issue-worker: #{candidate.number}: already assigned to {candidate.assignees[1].login}, skipping`)
		elseif branchExists(git.repoRoot(), branch) and not shell.succeeds(("test -d %s"):format(shell.quote(worktreePath))) then
			ptah.log(`issue-worker: #{candidate.number}: branch {branch} exists without its worktree, skipping`)
		else
			-- Read the issue detail *before* claiming: a transport failure
			-- here must not leave an assigned issue with no bookkeeping
			-- (assignment is the claim, and future runs skip assigned
			-- issues).
			local viewed = gh.run({ "issue", "view", tostring(candidate.number), "--json", "title,body,url" }, { json = true })
			if not viewed.ok then
				error(`issue-worker: gh issue view #{candidate.number} failed: {viewed.stderr}`, 0)
			end
			local detail = viewed.json :: { title: string, body: string?, url: string }
			if not claim(candidate.number, login) then
				ptah.log(`issue-worker: #{candidate.number}: claim lost to a concurrent run, skipping`)
			else
				return {
					number = candidate.number,
					title = detail.title,
					url = detail.url,
					body = if detail.body ~= nil then detail.body else "",
				}
			end
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Stage prompts (playbook-owned; repo prose arrives through repoBrief)
-- ---------------------------------------------------------------------------

local function triagePrompt(cfg: Resolved, issue: Issue, dir: string): string
	local routeLines: { string } = {}
	if cfg.openspec then
		table.insert(
			routeLines,
			`- route "openspec" — the work changes behavior a spec should govern: a new capability, a change spanning several areas, or an area covered by openspec/specs/. Author the change proposal NOW using the openspec-propose skill (the openspec CLI is on PATH): a short kebab-case name, with proposal, design, spec deltas, and tasks complete enough that a reviewer could groom it. Report that name as changeName.`
		)
	end
	table.insert(
		routeLines,
		`- route "direct" — a small, mechanical, well-localized change (typo, small fix, refactor, dependency bump, docs). Do NOT implement anything now. Put your implementation plan in the rationale.`
	)
	table.insert(
		routeLines,
		`- route "reject" — ONLY when the issue lacks critical or blocking detail, or needs an architectural decision from a human. State exactly what is missing or which decision is needed in the rationale.`
	)
	local changeField = if cfg.openspec then ", changeName" else ""
	return table.concat({
		`You are the triage step of the issueWorker playbook, operating in the repository worktree: {dir}`,
		"",
		`Everything you write lands on this issue's delivery branch — work only inside this worktree.`,
		"",
		"The issue you are triaging:",
		"",
		`#{issue.number} {issue.title}`,
		"",
		issue.body,
		"",
		`Decide the route, then submit the verdict with this session's ptah result tool (fields: route, rationale, commitType{changeField}).`,
		table.concat(routeLines, "\n"),
		`Also submit commitType: the conventional-commit type (one of {table.concat(cfg.commitTypes, ", ")}) that fits the change — it names the delivered PR's title on every route.`,
		"",
		`Read AGENTS.md and the relevant code and issue comments (gh issue view {issue.number} --comments) before deciding. Keep the rationale to a few sentences.` .. briefSuffix(cfg),
	}, "\n")
end

local function directPrompt(cfg: Resolved, issue: Issue, triageNotes: string): string
	return table.concat({
		`You are the implementation step of the issueWorker playbook, operating in the repository worktree.`,
		"",
		`Work only inside this worktree, on the branch it has checked out. Follow AGENTS.md.`,
		"",
		"The issue to implement:",
		"",
		`#{issue.number} {issue.title}`,
		"",
		issue.body,
		"",
		"Triage notes (the plan written while deciding this is a direct edit):",
		"",
		triageNotes,
		"",
		`Implement the change. Keep it minimal and focused on the issue; run just format on what you touch. Commit as you go with {commitInvocation(cfg.commitSignArgs)} and messages a maintainer would write.`,
		"",
		`Do NOT push and do NOT open a pull request — the next stage owns delivery. Finish with a one-paragraph summary of what you changed and the commits you created (git log origin/{cfg.baseBranch}..HEAD --oneline).`,
		briefSuffix(cfg),
	}, "\n")
end

local function deliveryPrompt(cfg: Resolved, issue: Issue, branch: string, prTitle: string): string
	local gateLines: { string } = {}
	for _, command in cfg.gateCommands do
		table.insert(gateLines, "- `" .. command .. "`")
	end
	return table.concat({
		`You are the delivery step of the issueWorker playbook, operating in the repository worktree (branch {branch}).`,
		"",
		"The implementation is committed. Finish the delivery:",
		"",
		`1. If anything is uncommitted, commit it with {commitInvocation(cfg.commitSignArgs)}.`,
		"2. Run the repository gate commands and fix what they report, committing the fixes:",
		table.concat(gateLines, "\n"),
		`3. git fetch origin {cfg.baseBranch}. If HEAD is behind origin/{cfg.baseBranch}, merge origin/{cfg.baseBranch} into this branch — do not rebase, signed commits must be preserved — and resolve; if the merge conflicts beyond what you can resolve correctly, stop and say so.`,
		`4. git push -u origin {branch}.`,
		"5. Open the pull request (write the body to a temp file first). The title is fixed — the repository requires a conventional-commit title and it is already composed; use it exactly as given:",
		"",
		`gh pr create --base {cfg.baseBranch} --head {branch} --assignee @me --title {shell.quote(prTitle)} --body-file <temp file>`,
		"",
		`The body's first line must be exactly \`Closes #{issue.number}\`, followed by a blank line and a concise summary of the change.`,
		"",
		"Then submit the pull request URL with the ptah result tool (field: prUrl).",
		briefSuffix(cfg),
	}, "\n")
end

-- ---------------------------------------------------------------------------
-- Triage
-- ---------------------------------------------------------------------------

local function verdictSchema(cfg: Resolved): { [string]: any }
	local routes = { "direct", "reject" }
	if cfg.openspec then
		table.insert(routes, "openspec")
	end
	return {
		type = "object",
		additionalProperties = false,
		properties = {
			route = { type = "string", enum = routes },
			rationale = { type = "string" },
			commitType = { type = "string", enum = cfg.commitTypes },
			changeName = { type = "string" },
		},
		required = { "route", "rationale", "commitType" },
	}
end

local function validateVerdict(cfg: Resolved, submitted: SubmittedVerdict): Verdict?
	local route = submitted.route
	if route == nil then
		return nil
	end
	local routed = route == "direct" or route == "reject" or (cfg.openspec and route == "openspec")
	if not routed then
		return nil
	end
	local rationale = submitted.rationale
	if rationale == nil or rationale == "" then
		return nil
	end
	local commitType = submitted.commitType
	if commitType == nil or commitType == "" then
		return nil
	end
	local known = false
	for _, candidate in cfg.commitTypes do
		if candidate == commitType then
			known = true
			break
		end
	end
	if not known then
		return nil
	end
	local changeName = submitted.changeName
	if route == "openspec" and (changeName == nil or changeName == "") then
		return nil
	end
	local resolvedRoute: string = route
	return { route = resolvedRoute, rationale = rationale, commitType = commitType, changeName = changeName }
end

local function runTriage(cfg: Resolved, work: Agent, issue: Issue, dir: string): Verdict
	local session: Session = work:session({ id = "triage", resultSchema = verdictSchema(cfg) })
	sessionConfig.apply(session, cfg.sessionConfig)
	for attempt = 1, cfg.maxAttempts do
		local retryNote = if attempt == 1
			then ""
			else "\n\nYour previous answer carried no usable result submission. Answer again and submit the verdict with the ptah result tool."
		local result = session:prompt(triagePrompt(cfg, issue, dir) .. retryNote)
		local submitted = result.result :: SubmittedVerdict?
		if submitted ~= nil then
			local verdict = validateVerdict(cfg, submitted)
			if verdict ~= nil then
				session:close()
				return verdict
			end
		end
		ptah.log(`issue-worker: triage submitted no valid verdict (attempt {attempt}/{cfg.maxAttempts})`)
	end
	session:close()
	error("issueWorker: triage produced no usable verdict within the retry budget", 0)
end

-- ---------------------------------------------------------------------------
-- Direct implementation
-- ---------------------------------------------------------------------------

local function runDirect(cfg: Resolved, work: Agent, issue: Issue, triageNotes: string): ()
	local session: Session = work:session({ id = "direct-implement" })
	sessionConfig.apply(session, cfg.sessionConfig)
	session:prompt(directPrompt(cfg, issue, triageNotes))
	session:close()
end

-- ---------------------------------------------------------------------------
-- Delivery (one typed-result session, then deterministic re-checks)
-- ---------------------------------------------------------------------------

local function ghPrTitle(prUrl: string): string
	local outcome = gh.run({ "pr", "view", prUrl, "--json", "title" }, { json = true })
	if not outcome.ok then
		error(`issue-worker: could not read the PR title for {prUrl}: {outcome.stderr}`, 0)
	end
	local data = outcome.json :: { title: string }
	return data.title
end

-- The title is script-owned: restate it rather than fail the run; only a
-- title that still does not match after the edit is a failure.
local function verifyPrTitle(prUrl: string, expected: string): ()
	local actual = ghPrTitle(prUrl)
	if actual == expected then
		return
	end
	local edit = gh.run({ "pr", "edit", prUrl, "--title", expected })
	if not edit.ok then
		error(`issue-worker: could not correct the PR title on {prUrl}: {edit.stderr}`, 0)
	end
	actual = ghPrTitle(prUrl)
	if actual ~= expected then
		error(`issue-worker: PR title did not stick: expected {expected}, got {actual}`, 0)
	end
end

local function runDelivery(cfg: Resolved, work: Agent, issue: Issue, branch: string, commitType: string): string
	local prTitle = `{commitType}: {issue.title}`
	local session: Session = work:session({ id = "deliver", resultSchema = DELIVERY_SCHEMA })
	sessionConfig.apply(session, cfg.sessionConfig)
	local prUrl: string? = nil
	for attempt = 1, cfg.maxAttempts do
		local retryNote = if attempt == 1
			then ""
			else "\n\nYour previous answer did not submit the PR URL. Answer again and submit it with the ptah result tool."
		local result = session:prompt(deliveryPrompt(cfg, issue, branch, prTitle) .. retryNote)
		local submitted = result.result :: { prUrl: string }?
		if submitted ~= nil and submitted.prUrl ~= nil and submitted.prUrl ~= "" then
			prUrl = submitted.prUrl
			break
		end
		ptah.log(`issue-worker: delivery submitted no PR URL (attempt {attempt}/{cfg.maxAttempts})`)
	end
	session:close()
	if prUrl == nil then
		error("issueWorker: delivery produced no PR URL within the retry budget", 0)
	end
	return prUrl
end

-- Deterministic re-checks over the URL the delivery session reported:
-- never trust the session's prose. This runs after the URL is published to
-- the outcome, so a re-check failure still carries the pull request the
-- session opened.
local function verifyDelivery(cfg: Resolved, issue: Issue, dir: string, branch: string, commitType: string, prUrl: string): ()
	local prTitle = `{commitType}: {issue.title}`
	local ahead = git.commitsAhead(dir, cfg.baseBranch, branch)
	if ahead < 1 then
		error(`issueWorker: branch {branch} has no commits ahead of origin/{cfg.baseBranch}`, 0)
	end
	if parsePrUrl(prUrl) == nil then
		error(`issueWorker: reported PR URL does not look like a pull request URL: {prUrl}`, 0)
	end
	local upToDate = shell.succeeds(
		("git -C %s merge-base --is-ancestor origin/%s HEAD"):format(shell.quote(dir), shell.quote(cfg.baseBranch))
	)
	if not upToDate then
		error(`issueWorker: branch {branch} is not up to date with origin/{cfg.baseBranch} (merge, never rebase)`, 0)
	end
	verifyPrTitle(prUrl, prTitle)
end

-- ---------------------------------------------------------------------------
-- The lifecycle
-- ---------------------------------------------------------------------------

local function processImpl(cfg: Resolved, issue: Issue): Outcome
	-- The delivered pull-request URL is hoisted so the catch-all failure
	-- outcome can carry it once delivery has opened one, even when a
	-- later stage (review, title check) raises.
	local prUrl: string? = nil

	local function pipeline(): Outcome
		local repoRoot = git.repoRoot()
		local branch = `{cfg.branchPrefix}{issue.number}`
		local dir = git.ensure(repoRoot, cfg.worktreeDir, cfg.baseBranch, branch)
		-- Wrap the configured handles once per issue: every session the
		-- playbook or a nested playbook creates runs in the worktree, and
		-- no stage sets `cwd` itself.
		local work = stdAgent.inDirectory(cfg.agent, dir)
		local judge = stdAgent.inDirectory(cfg.judgeAgent, dir)
		local reporter = stdAgent.inDirectory(cfg.reporterAgent, dir)

		local verdict = runTriage(cfg, work, issue, dir)
		ptah.log(`issue-worker: #{issue.number} triage route={verdict.route}`)

		if verdict.route == "reject" then
			markRejected(cfg, issue.number, verdict.rationale)
			return { status = "rejected", issue = issue, prUrl = nil, reason = verdict.rationale }
		end

		if verdict.route == "openspec" then
			local changeName = verdict.changeName
			if changeName == nil or changeName == "" then
				error("issueWorker: triage returned the openspec route without a change name", 0)
			end
			git.requireChangeDir(dir, changeName)
			local ops = openspecPlaybook.new({
				agent = work,
				judgeAgent = judge,
				sessionConfig = cfg.sessionConfig,
				judgeSessionConfig = cfg.judgeSessionConfig,
			})
			ops:groom(changeName)
			ops:implement(changeName)
			ops:verify(changeName)
		else
			runDirect(cfg, work, issue, verdict.rationale)
		end

		local delivered = runDelivery(cfg, work, issue, branch, verdict.commitType)
		-- Publish the URL before the remaining deterministic re-checks so a
		-- later failure still carries the pull request the session opened.
		-- A reported value that is not a pull URL is not published: no pull
		-- request URL is known to exist.
		if parsePrUrl(delivered) ~= nil then
			prUrl = delivered
		end
		verifyDelivery(cfg, issue, dir, branch, verdict.commitType, delivered)
		ptah.log(`issue-worker: #{issue.number} delivered {delivered}`)

		-- Review first; a CI repair push never re-runs the review.
		local loop = prReviewLoop.new({
			agent = work,
			judgeAgent = judge,
			reporterAgent = reporter,
			sessionConfig = cfg.sessionConfig,
			judgeSessionConfig = cfg.judgeSessionConfig,
			reporterSessionConfig = cfg.reporterSessionConfig,
			maxIterations = cfg.reviewMaxIterations,
			dryRun = false,
		})
		local review = loop:review(delivered)
		if review.status ~= "converged" then
			-- A review loop that does not converge mirrors a CI `unresolved`
			-- outcome: record the failure bookkeeping and fail the run rather
			-- than reporting the issue delivered with open blocking findings.
			local detail = if review.verdict ~= "" then review.verdict else "no verdict reported"
			local reason = `issueWorker: the nested PR review loop did not converge (status {review.status}): {detail}`
			recordFailure(cfg, issue.number, reason)
			return { status = "failed", issue = issue, prUrl = delivered, reason = reason }
		end

		local gate = ciGatePlaybook.new({
			agent = work,
			sessionConfig = cfg.sessionConfig,
			commitSignArgs = cfg.commitSignArgs,
			timeoutSeconds = cfg.ciTimeoutSeconds,
			pollSeconds = cfg.ciPollSeconds,
			repairAttempts = cfg.ciRepairAttempts,
		})
		local gateOutcome = gate:watch(delivered)
		if gateOutcome.status ~= "green" then
			local reason = if gateOutcome.reason ~= nil then gateOutcome.reason else "CI checks did not pass"
			recordFailure(cfg, issue.number, reason)
			return { status = "failed", issue = issue, prUrl = delivered, reason = reason }
		end

		commentDelivered(issue.number, delivered)
		return { status = "delivered", issue = issue, prUrl = delivered, reason = nil }
	end

	local ok, result = pcall(pipeline)
	if ok then
		return result
	end
	local message = shell.errorMessage(result)
	ptah.log(`issue-worker: #{issue.number} failed: {message}`)
	recordFailure(cfg, issue.number, message)
	return { status = "failed", issue = issue, prUrl = prUrl, reason = message }
end

local function runImpl(cfg: Resolved): Outcome
	-- Pickup is a deterministic stage with no outcome of its own: a
	-- transport failure is returned as a `failed` outcome rather than
	-- propagated. The issue detail is read before the claim (see
	-- `pickupImpl`), so no claim can be left stranded here.
	local picked, issue = pcall(pickupImpl, cfg)
	if not picked then
		local message = shell.errorMessage(issue)
		ptah.log(`issue-worker: pickup failed: {message}`)
		return { status = "failed", issue = nil, prUrl = nil, reason = message }
	end
	if issue == nil then
		ptah.log(`issue-worker: no open issue labeled {cfg.readyLabel}; nothing to do`)
		return { status = "idle", issue = nil, prUrl = nil, reason = nil }
	end
	ptah.log(`issue-worker: claimed #{issue.number}: {issue.title}`)
	return processImpl(cfg, issue)
end

local M = {}

function M.new(config: Config): Instance
	local cfg: Resolved = {
		agent = config.agent,
		judgeAgent = config.judgeAgent,
		reporterAgent = config.reporterAgent,
		sessionConfig = config.sessionConfig,
		judgeSessionConfig = config.judgeSessionConfig,
		reporterSessionConfig = config.reporterSessionConfig,
		readyLabel = config.readyLabel,
		blockedLabel = config.blockedLabel,
		baseBranch = config.baseBranch,
		branchPrefix = config.branchPrefix,
		gateCommands = config.gateCommands,
		worktreeDir = if config.worktreeDir ~= nil then config.worktreeDir else DEFAULT_WORKTREE_DIR,
		commitTypes = if config.commitTypes ~= nil then config.commitTypes else DEFAULT_COMMIT_TYPES,
		commitSignArgs = if config.commitSignArgs ~= nil then config.commitSignArgs else DEFAULT_SIGN_ARGS,
		pickupLimit = if config.pickupLimit ~= nil then config.pickupLimit else DEFAULT_PICKUP_LIMIT,
		maxAttempts = if config.maxAttempts ~= nil then config.maxAttempts else DEFAULT_MAX_ATTEMPTS,
		reviewMaxIterations = if config.reviewMaxIterations ~= nil then config.reviewMaxIterations
			else DEFAULT_REVIEW_MAX_ITERATIONS,
		ciTimeoutSeconds = if config.ciTimeoutSeconds ~= nil then config.ciTimeoutSeconds else DEFAULT_CI_TIMEOUT_SECONDS,
		ciPollSeconds = if config.ciPollSeconds ~= nil then config.ciPollSeconds else DEFAULT_CI_POLL_SECONDS,
		ciRepairAttempts = if config.ciRepairAttempts ~= nil then config.ciRepairAttempts else DEFAULT_CI_REPAIR_ATTEMPTS,
		openspec = config.openspec == true,
		repoBrief = config.repoBrief,
	}
	return {
		run = function(_self: Instance): Outcome
			return runImpl(cfg)
		end,
		pickup = function(_self: Instance): Issue?
			return pickupImpl(cfg)
		end,
		process = function(_self: Instance, issue: Issue): Outcome
			return processImpl(cfg, issue)
		end,
	}
end

return M
