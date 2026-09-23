--!strict
-- Factory composition playbook: drain a repository's labeled issue queue
-- into reviewed pull requests. It composes the issue, openspec, and pr
-- playbooks and constructs those instances internally from its own
-- data-only config (docs/adr/0006-factory-composition-playbook.md): config
-- accepts no playbook instances, and the work/judge/reporter agent handles
-- are the only ptah runtime handles. One issue end-to-end is
-- `issueToPR(number?)` — the given issue when a number is passed, else the
-- oldest eligible — and `drain()` loops it in scan mode until the queue
-- holds no eligible issue. `initLabels(vocabulary?)` is the module-level,
-- agent-free label alignment (bootstrap and drift repair).
--
-- Each issue runs in its own worktree on the fixed branch `issue-<n>`,
-- branched off `origin/<base>` (the required `base` config names both the
-- worktree ref and the pull request's base — one field, per design D3;
-- nobody has ever wanted them to split). openspec is mandatory in v1: a
-- claimed issue is resolved to an existing openspec change — driven through
-- groom → implement → verify (which syncs and archives) — or implemented as
-- a direct edit when no change applies. The delivery prompt is a
-- library-owned skeleton carrying the correctness lessons every run needs
-- (commit on the pre-created branch, push with `-u --force-with-lease` so a
-- resumed run stays safe and the review loop's later bare `git push` lands
-- on the PR branch, `Closes #<n>` in the body so the issue closes on merge,
-- `gh pr create --base <base>`, plain Conventional Commits), with the
-- configured `prContract` free-text fragment injected at its declared point;
-- the direct-edit prompt carries the `conventions` fragment the same way.
-- Repo-specific law (signing, commit trailers, lint allowlists, CI
-- contracts) travels only in fragments — the skeleton never restates it.
-- The typed hand-offs are bounded: the change-resolution hand-off re-asks up
-- to `resolveChangeAttempts` times and the PR hand-off up to
-- `openPullRequestAttempts` times (default 3 each); exhaustion fails the
-- issue.
--
-- Outcomes are data discriminated on `status`: `pr-reviewed` (PR opened,
-- review converged), `pr-non-converged` (PR opened, review at its cap with
-- open blocking findings — a completed hand-off to the issue's human
-- reviewer, never recorded as a failure), `no-eligible-issue` (nothing left
-- to claim, with the scanned count), and `failed` (the run raised, with the
-- error message). The policies are laws, not config — all three consumer
-- shims agreed on them and none may drift: the drain's per-issue error
-- boundary (a failed issue is logged with its number, the loop continues,
-- the claim marker stays as the audit trail), teardown on the success path
-- only (a failed issue keeps its worktree), and non-converged-as-hand-off.
-- Session ids keep the shim shapes (`factory-resolve:<n>`,
-- `factory-direct:<n>`, `factory-pr:<n>`) and log lines keep the `factory:`
-- prefix for grep compatibility.

local gh = require("../../std/gh")
local sessionConfig = require("../../std/session-config")
local worktree = require("../../std/worktree")
local issuePlaybook = require("../issue/playbook")
local openspecPlaybook = require("../openspec/playbook")
local prPlaybook = require("../pr/playbook")
local defaultVocabulary = require("./default-vocabulary")

-- One declared label: the name is matched exactly (no renames — a renamed
-- label is a new label to create and an unlisted one left untouched), the
-- color is the GitHub hex code (a leading `#` is accepted and stripped),
-- and the description is managed when declared: alignment updates a drifted
-- description to the declared text, and an entry without one leaves
-- whatever description the repository carries.
export type Label = {
	name: string,
	color: string,
	description: string?,
}

-- The initLabels summary: which labels were created, which were updated
-- (drift repaired), and how many already matched. Data, so a calling script
-- can log or gate on what alignment did.
export type AlignmentSummary = {
	created: { string },
	updated: { string },
	unchanged: number,
}

export type Config = {
	-- Work agent handle: the resolution, direct-edit, and delivery sessions
	-- here, plus (through the internally constructed playbooks) the
	-- openspec lifecycle's and the review loop's work sessions.
	agent: Agent,
	-- Judge agent handle for the typed predicates and findings sessions.
	judgeAgent: Agent,
	-- Reporter agent handle for the PR review report's body session.
	reporterAgent: Agent,
	-- Ordered session-config entries applied to every work session the
	-- factory creates directly (resolve, direct edit, delivery) and
	-- forwards to the composed playbooks' work sessions.
	sessionConfig: { sessionConfig.Entry }?,
	-- Ordered session-config entries applied to every judge session
	-- (forwarded into the composed playbooks and their predicates).
	judgeSessionConfig: { sessionConfig.Entry }?,
	-- Ordered session-config entries applied to every reporter session.
	reporterSessionConfig: { sessionConfig.Entry }?,
	-- The repo-configured queue label: required, no default — the label
	-- vocabulary is the repository's, never the playbook's.
	queueLabel: string,
	-- Added on claim for human-legible queue state only (the issue
	-- playbook's semantics, forwarded verbatim).
	claimedLabel: string?,
	-- The delivery base branch: required, no default — the delivery base is
	-- the repository's. Each issue's worktree branches from `origin/<base>`
	-- and its pull request targets `base`.
	base: string,
	-- Free-text prompt fragment injected into the direct-edit prompt:
	-- docs to read, conventions to follow, the test commands to run.
	conventions: string?,
	-- Free-text prompt fragment injected into the delivery prompt: signing,
	-- commit trailers, PR title/body contracts, CI contracts to read.
	prContract: string?,
	-- The composed review loop's convergence cap (default 10).
	maxReviewIterations: number?,
	-- Bound on the change-resolution hand-off (default 3): exhaustion fails
	-- the issue.
	resolveChangeAttempts: number?,
	-- Bound on the PR hand-off (default 3): exhaustion fails the issue.
	openPullRequestAttempts: number?,
	-- Whether the factory may relocate a live occupant of the issue branch
	-- before provisioning it (default `true`): the occupant worktree — the
	-- operator's prep worktree for this very issue, or a manual checkout —
	-- is torn down with default (refuse-dirty) options so the claim can
	-- re-attach the surviving branch at the canonical worktree. A teardown
	-- refusal fails the issue naming the path and the remedy; `false`
	-- restores provision's occupant raise.
	removeOccupantWorktree: boolean?,
}

export type PrReviewed = {
	status: "pr-reviewed",
	-- The claimed issue's number.
	number: number,
	prUrl: string,
	verdict: string,
}

export type PrNonConverged = {
	status: "pr-non-converged",
	number: number,
	prUrl: string,
	verdict: string,
}

export type NoEligibleIssue = {
	status: "no-eligible-issue",
	-- How many issues the scan examined under the full eligibility scope
	-- before none proved eligible (the issue playbook's semantics).
	scanned: number,
}

export type Failed = {
	status: "failed",
	-- The issue whose run raised.
	number: number,
	error: string,
}

-- Outcomes as data, discriminated on `status`.
export type Outcome = PrReviewed | PrNonConverged | NoEligibleIssue | Failed

export type Instance = {
	-- Drive one issue end to end: claim (the given number only if eligible —
	-- an ineligible one raises with the reason — or the oldest eligible),
	-- provision the worktree, resolve the change or edit directly, open the
	-- issue-linked PR, run the convergent review, tear down on the success
	-- path. A raised run returns the `failed` outcome instead: the worktree
	-- is kept and the claim marker stays as the audit trail.
	issueToPR: (self: Instance, number: number?) -> Outcome,
	-- Loop `issueToPR()` in scan mode until the queue holds no eligible
	-- issue, returning the collected outcomes. Each issue runs behind the
	-- per-issue error boundary (a failed issue is logged and the loop
	-- continues); the last element is the `no-eligible-issue` stop outcome
	-- carrying the scanned count. A failure of the claim phase itself (a
	-- transport error, no issue involved) aborts the drain — retrying a
	-- broken scan would never terminate.
	drain: (self: Instance) -> { Outcome },
}

local ERROR_PREFIX = "factory"

local DEFAULT_MAX_REVIEW_ITERATIONS = 10
local DEFAULT_RESOLVE_ATTEMPTS = 3
local DEFAULT_OPEN_PR_ATTEMPTS = 3

-- The typed hand-off contracts: the resolver submits the change's directory
-- name (empty string: no change applies, direct edit), the committer submits
-- the PR URL.
local CHANGE_SCHEMA: { [string]: any } = {
	type = "object",
	properties = { change = { type = "string" } },
	required = { "change" },
}

local PR_URL_SCHEMA: { [string]: any } = {
	type = "object",
	properties = { prUrl = { type = "string" } },
	required = { "prUrl" },
}

-- ---------------------------------------------------------------------------
-- Label alignment (module-level, agent-free)
-- ---------------------------------------------------------------------------

local LABELS_PATH = "/repos/{owner}/{repo}/labels"

-- Flatten `gh api --paginate --slurp` output: a slurped response is an array
-- of pages, each page an array of label entries; a flat response is an array
-- of entries. A label entry always carries `name`, a page never does.
local function flattenLabels(raw: any): { any }
	local out: { any } = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, entry in raw do
		if type(entry) == "table" and entry.name == nil then
			for _, item in entry do
				table.insert(out, item)
			end
		else
			table.insert(out, entry)
		end
	end
	return out
end

-- GitHub stores colors as lowercase hex without the leading `#`; compare and
-- write in that canonical form so a `#0E8A16` config matches `0e8a16` on the
-- wire (idempotency never depends on spelling).
local function normalizeColor(color: string): string
	local stripped = (string.gsub(color, "^#", ""))
	return string.lower(stripped)
end

-- Percent-encode a label name for its REST path (names may carry spaces,
-- slashes, emoji; the unreserved set passes through).
local function escapeLabelName(name: string): string
	return (
		string.gsub(name, "[^%w%-_%.~]", function(c: string): string
			return string.format("%%%02X", string.byte(c))
		end)
	)
end

local M = {}

-- Align the repository's GitHub labels to `vocabulary` (the built-in
-- canonical default when no argument is passed; a configured vocabulary
-- replaces the default wholesale, never merges): read the current labels,
-- create the missing, update drifted colors and declared-but-drifted
-- descriptions, never delete an unlisted label, never rename. Agent-free by
-- design — pure `gh` transport, no sessions. Runs against the invocation
-- directory's repository, exactly like bare `gh` (GH_REPO overrides; there
-- is no repo field). Re-running on an aligned repository writes nothing.
function M.initLabels(vocabulary: { Label }?): AlignmentSummary
	local labels: { Label } = if vocabulary ~= nil then vocabulary else defaultVocabulary

	local outcome = gh.run({ "api", "--method", "GET", "--paginate", "--slurp", LABELS_PATH }, { json = true })
	if not outcome.ok then
		error(`{ERROR_PREFIX}: could not read the repository's labels: {outcome.stderr}`)
	end
	local current: { [string]: { color: string, description: string } } = {}
	for _, entry in flattenLabels(outcome.json) do
		if type(entry) == "table" and type(entry.name) == "string" then
			current[entry.name :: string] = {
				color = if type(entry.color) == "string" then entry.color else "",
				description = if type(entry.description) == "string" then entry.description else "",
			}
		end
	end

	local created: { string } = {}
	local updated: { string } = {}
	local unchanged = 0
	for _, label in labels do
		local name = label.name
		if name == nil or name == "" then
			error(`{ERROR_PREFIX}: a vocabulary entry carries no label name`)
		end
		local color = normalizeColor(label.color)
		local existing = current[name]
		if existing == nil then
			local args: { string } = { "api", "--method", "POST", LABELS_PATH, "-f", `name={name}` }
			table.insert(args, "-f")
			table.insert(args, `color={color}`)
			if label.description ~= nil then
				table.insert(args, "-f")
				table.insert(args, `description={label.description}`)
			end
			local write = gh.run(args)
			if not write.ok then
				error(`{ERROR_PREFIX}: could not create the label "{name}": {write.stderr}`)
			end
			table.insert(created, name)
		else
			local drifted = false
			local args: { string } = { "api", "--method", "PATCH", `{LABELS_PATH}/{escapeLabelName(name)}` }
			if normalizeColor(existing.color) ~= color then
				table.insert(args, "-f")
				table.insert(args, `color={color}`)
				drifted = true
			end
			if label.description ~= nil and existing.description ~= (label.description :: string) then
				table.insert(args, "-f")
				table.insert(args, `description={label.description}`)
				drifted = true
			end
			if drifted then
				local write = gh.run(args)
				if not write.ok then
					error(`{ERROR_PREFIX}: could not update the label "{name}": {write.stderr}`)
				end
				table.insert(updated, name)
			else
				unchanged += 1
			end
		end
	end

	ptah.log(
		`{ERROR_PREFIX}: label alignment: created {#created}, updated {#updated}, unchanged {unchanged}`
	)
	return { created = created, updated = updated, unchanged = unchanged }
end

-- ---------------------------------------------------------------------------
-- The playbook
-- ---------------------------------------------------------------------------

function M.new(config: Config): Instance
	-- Required knobs have no defaults: the queue label and the delivery base
	-- are the repository's, never the playbook's. The type system reports a
	-- missing field to a typed caller; these guards name the field for an
	-- untyped one.
	if (config.queueLabel :: string?) == nil then
		error("factory: queueLabel is required (the queue label is the repository's, never the playbook's)")
	end
	if (config.base :: string?) == nil then
		error("factory: base is required (the delivery base is the repository's, never the playbook's)")
	end

	local workAgent: Agent = config.agent
	local judgeAgent: Agent = config.judgeAgent
	local reporterAgent: Agent = config.reporterAgent
	local workEntries: { sessionConfig.Entry }? = config.sessionConfig
	local base: string = config.base
	local conventions: string? = config.conventions
	local prContract: string? = config.prContract
	local maxReviewIterations = if config.maxReviewIterations ~= nil
		then config.maxReviewIterations
		else DEFAULT_MAX_REVIEW_ITERATIONS
	local resolveAttempts = if config.resolveChangeAttempts ~= nil
		then config.resolveChangeAttempts
		else DEFAULT_RESOLVE_ATTEMPTS
	local openPrAttempts = if config.openPullRequestAttempts ~= nil
		then config.openPullRequestAttempts
		else DEFAULT_OPEN_PR_ATTEMPTS
	-- Default on: claim-marker serialization means the only possible
	-- occupants of `issue-<n>` are the operator's own artifacts, so the
	-- documented prep hand-off just works; `false` keeps provision's
	-- occupant raise as the tripwire.
	local removeOccupantWorktree = config.removeOccupantWorktree ~= false

	-- The issue playbook is agent-free: one instance per factory instance.
	local issueOps = issuePlaybook.new({
		queueLabel = config.queueLabel,
		claimedLabel = config.claimedLabel,
	})

	-- An agent reads the claimed issue and identifies which *existing*
	-- openspec change should be applied to resolve it. No change is created
	-- here. An empty submitted name means no change applies: the issue is a
	-- direct edit. The listing is the worktree's, so only changes already
	-- merged to the base are visible; a change that exists only in some
	-- unmerged branch resolves as a direct edit. Bounded by
	-- resolveChangeAttempts: a resolver that never submits is designed
	-- degradation until the attempts are exhausted.
	local function resolveChange(brief: issuePlaybook.Brief, workingDir: string): string?
		local session: Session = workAgent:session({
			id = `factory-resolve:{brief.number}`,
			cwd = workingDir,
			resultSchema = CHANGE_SCHEMA,
		})
		sessionConfig.apply(session, workEntries)

		local prompt = table.concat({
			`Identify which existing openspec change should be applied to resolve GitHub issue #{brief.number}.`,
			"",
			`Title: {brief.title}`,
			`URL: {brief.url}`,
			"",
			"Body:",
			brief.body,
			"",
			"If the issue names an openspec change, use that name. Otherwise list the changes under `openspec/changes/` and pick the one whose scope matches this issue. Do not create a new change and do not implement anything.",
			`Submit that change's directory name through this session's ptah result tool as \{ "change": "<kebab-case-name>" \}, or an empty string if no change applies and the issue is a direct edit.`,
		}, "\n")

		local change: string? = nil
		local resolved = false
		for attempt = 1, resolveAttempts do
			local outcome = session:prompt(prompt)
			local result = outcome.result
			if type(result) == "table" and type(result.change) == "string" then
				change = if result.change == "" then nil else result.change
				resolved = true
				break
			end
			ptah.log(`{ERROR_PREFIX}: resolver submitted no change name (attempt {attempt}/{resolveAttempts})`)
		end
		session:close()
		if not resolved then
			error(`{ERROR_PREFIX}: could not identify an openspec change for issue #{brief.number}`)
		end
		return change
	end

	-- No openspec change applies: an agent implements the issue directly in
	-- the issue's worktree, under the `conventions` fragment at its declared
	-- injection point. The PR review loop that follows is the convergence
	-- step.
	local function directEdit(brief: issuePlaybook.Brief, workingDir: string): ()
		local session: Session = workAgent:session({
			id = `factory-direct:{brief.number}`,
			cwd = workingDir,
		})
		sessionConfig.apply(session, workEntries)

		local lines = {
			`Implement GitHub issue #{brief.number} directly in this repository. No openspec change applies to it.`,
			"",
			`Title: {brief.title}`,
			`URL: {brief.url}`,
			"",
			"Body:",
			brief.body,
			"",
			"Make the edits the issue asks for, following the repository's conventions, and run the relevant format and test commands before finishing. Do not create an openspec change.",
		}
		if conventions ~= nil then
			table.insert(lines, "")
			table.insert(lines, "## Repository conventions")
			table.insert(lines, conventions :: string)
		end
		session:prompt(table.concat(lines, "\n"))
		session:close()
	end

	-- The committer owns the git mechanics (commit, push, `gh pr create`)
	-- and returns the PR URL as a typed result. The delivery prompt is the
	-- library-owned skeleton: the branch `issue-<n>` is already created and
	-- checked out, the push is `-u --force-with-lease` (the lease is safe on
	-- resumed runs; `-u` repoints the upstream the branch inherited from
	-- `origin/<base>` so the review loop's later bare `git push` lands on
	-- the PR branch), and the body carries `Closes #<n>` — the issue's
	-- release protocol, since the claim is retired by the issue closing.
	-- The `prContract` fragment rides at its declared injection point; the
	-- skeleton's structure is unchanged by the fragment's content. Bounded
	-- by openPullRequestAttempts: exhaustion fails the issue.
	local function openPullRequest(brief: issuePlaybook.Brief, change: string?, workingDir: string): string
		local session: Session = workAgent:session({
			id = `factory-pr:{brief.number}`,
			cwd = workingDir,
			resultSchema = PR_URL_SCHEMA,
		})
		sessionConfig.apply(session, workEntries)

		local summary = if change ~= nil
			then `The openspec change "{change}" for GitHub issue #{brief.number} is implemented, verified, synced, and archived.`
			else `The changes for GitHub issue #{brief.number} are implemented.`
		local lines = {
			summary,
			`Your working directory is the issue's worktree, with the branch "issue-{brief.number}" already checked out. Commit the uncommitted changes (except the .ptah directory) with a Conventional Commits message that references issue #{brief.number}, push that branch to the remote with "git push -u --force-with-lease origin issue-{brief.number}" — both flags are safe on a resumed run, and "-u" points the branch's upstream at the pull request branch so the review loop's later bare "git push" lands there — and open a pull request against {base} with "gh pr create --base {base}". Do not create, rename, or switch away from the branch.`,
			`Include "Closes #{brief.number}" in the pull request body so the issue closes when the pull request merges.`,
		}
		if prContract ~= nil then
			table.insert(lines, "")
			table.insert(lines, "## Repository contract")
			table.insert(lines, prContract :: string)
		end
		table.insert(lines, `Submit the pull request URL through this session's ptah result tool as \{ "prUrl": "https://github.com/..." \}.`)
		local first = table.concat(lines, "\n")
		local retry = `Submit the pull request URL now through this session's ptah result tool as \{ "prUrl": "https://github.com/..." \}. If the pull request does not exist yet, create it first.`

		local prUrl: string? = nil
		local resolved = false
		for attempt = 1, openPrAttempts do
			local outcome = session:prompt(if attempt == 1 then first else retry)
			local result = outcome.result
			if type(result) == "table" and type(result.prUrl) == "string" and result.prUrl ~= "" then
				prUrl = result.prUrl
				resolved = true
				break
			end
			ptah.log(`{ERROR_PREFIX}: committer submitted no PR URL (attempt {attempt}/{openPrAttempts})`)
		end
		session:close()
		if not resolved then
			error(`{ERROR_PREFIX}: could not open a pull request for issue #{brief.number}`)
		end
		return prUrl :: string
	end

	-- One claimed issue, end to end. Every step runs inside the issue's
	-- worktree; a raise anywhere before the teardown leaves the worktree in
	-- place and the claim marker on the issue (the audit trail a human
	-- re-queues by hand). Both review outcomes are the success path: the
	-- worktree is torn down either way, and a non-converged review is a
	-- completed hand-off to the issue's human, not a failure.
	local function workIssue(brief: issuePlaybook.Brief): Outcome
		local number = brief.number
		local branch = `issue-{number}`

		-- The prep hand-off: the only possible live occupant of `issue-<n>`
		-- is the operator's own artifact (the prep worktree for this very
		-- issue, or a manual checkout — claim-marker serialization keeps
		-- rival owners out), so before provisioning the factory relocates
		-- it. Teardown with default (refuse-dirty) options never discards
		-- work: the branch survives teardown by contract and provision
		-- re-attaches it at the canonical worktree under its
		-- fast-forward-or-fail rule, commits preserved. A refusal (a dirty
		-- or locked occupant, or one containing this run's own working
		-- directory — the mechanism never removes the directory the factory
		-- executes from) fails the issue naming the path and the remedy,
		-- with the worktree and its contents untouched; the claim marker
		-- stays. With `removeOccupantWorktree = false` this step is skipped
		-- and provision's occupant raise is the behavior again.
		if removeOccupantWorktree then
			local occupant = worktree.liveOccupant({ branch = branch })
			if occupant ~= nil then
				ptah.log(`{ERROR_PREFIX}: issue #{number} relocating the worktree holding branch {branch} from {occupant}`)
				local removed = worktree.teardown({ path = occupant })
				if not removed.ok then
					error(`{ERROR_PREFIX}: issue #{number}: could not relocate the worktree holding branch {branch} at {occupant}: {removed.stderr} — commit, stash, or remove it by hand, then re-queue the issue`)
				end
			end
		end

		local wt = worktree.provision({
			name = branch,
			ref = `origin/{base}`,
			branch = branch,
			fetch = true,
		})
		ptah.log(`{ERROR_PREFIX}: issue #{number} worktree {wt.path} on branch {wt.branch}`)

		-- The openspec and pr playbooks take the working directory as
		-- constructor config, so each issue builds its own pair around its
		-- worktree instead of sharing a module-level instance.
		local opsx = openspecPlaybook.new({
			agent = workAgent,
			judgeAgent = judgeAgent,
			sessionConfig = workEntries,
			judgeSessionConfig = config.judgeSessionConfig,
			workingDir = wt.path,
		})
		local reviewLoop = prPlaybook.new({
			agent = workAgent,
			judgeAgent = judgeAgent,
			reporterAgent = reporterAgent,
			sessionConfig = workEntries,
			judgeSessionConfig = config.judgeSessionConfig,
			reporterSessionConfig = config.reporterSessionConfig,
			workingDir = wt.path,
			maxIterations = maxReviewIterations,
		})

		local change = resolveChange(brief, wt.path)
		if change ~= nil then
			ptah.log(`{ERROR_PREFIX}: issue #{number} resolved to openspec change "{change}"`)
			opsx:groom(change)
			opsx:implement(change)
			opsx:verify(change)
			ptah.log(`{ERROR_PREFIX}: change "{change}" implemented, verified, synced, and archived`)
		else
			ptah.log(`{ERROR_PREFIX}: issue #{number} has no openspec change; implementing directly`)
			directEdit(brief, wt.path)
		end

		local prUrl = openPullRequest(brief, change, wt.path)
		ptah.log(`{ERROR_PREFIX}: issue #{number} pull request: {prUrl}`)

		local review = reviewLoop:reviewFixLoop(prUrl)
		ptah.log(`{ERROR_PREFIX}: issue #{number} pr review-fix loop {review.status}: {review.verdict}`)

		-- Teardown is best-effort on the success path: a dirty refusal is
		-- logged, never fatal, and the branch survives either way.
		local removed = worktree.teardown(wt)
		if not removed.ok then
			ptah.log(`{ERROR_PREFIX}: issue #{number} worktree kept at {wt.path}: {removed.stderr}`)
		end

		if review.status == "converged" then
			return { status = "pr-reviewed", number = number, prUrl = prUrl, verdict = review.verdict }
		end
		return { status = "pr-non-converged", number = number, prUrl = prUrl, verdict = review.verdict }
	end

	local function issueToPR(number: number?): Outcome
		local picked = issueOps:pickUp(number)
		if picked.status == "no-eligible-issue" then
			return picked
		end
		local brief = picked.brief
		ptah.log(`{ERROR_PREFIX}: claimed issue #{brief.number} — {brief.title}`)

		-- The per-issue error boundary: a raised run becomes the `failed`
		-- outcome. The worktree is already kept (the teardown only runs on
		-- the success path) and the claim marker stays as the audit trail.
		local ok, result = pcall(workIssue, brief)
		if ok then
			return result :: Outcome
		end
		local message = tostring(result)
		ptah.log(`{ERROR_PREFIX}: issue #{brief.number} failed: {message}`)
		return { status = "failed", number = brief.number, error = message }
	end

	local instance: Instance = {
		issueToPR = function(_self: Instance, number: number?): Outcome
			return issueToPR(number)
		end,
		drain = function(_self: Instance): { Outcome }
			local outcomes: { Outcome } = {}
			while true do
				-- The per-issue `pcall` boundary around the whole operation.
				-- A run that still raises here is a claim-phase failure in
				-- scan mode: no issue is involved, so there is no issue to
				-- log or skip past, and continuing would re-scan into the
				-- same broken transport forever — the drain aborts instead.
				local ok, step = pcall(issueToPR) -- explicitly scan mode: no number
				if not ok then
					error(`{ERROR_PREFIX}: {tostring(step)}`)
				end
				local outcome = step :: Outcome
				table.insert(outcomes, outcome)
				if outcome.status == "no-eligible-issue" then
					ptah.log(
						`{ERROR_PREFIX}: no eligible issue left (scanned {outcome.scanned}); stopping`
					)
					break
				end
			end
			return outcomes
		end,
	}
	return instance
end

return M
