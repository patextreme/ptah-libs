--!strict
-- Factory workflow: the autonomous issue → reviewed PR loop.
--
-- Each iteration claims the oldest eligible issue (issue playbook), prepares
-- a worktree for it branched off WORKTREE_REF on the branch `issue-<n>`, and
-- runs every later step inside that worktree: resolving which existing
-- openspec change the issue maps to (or a direct edit when none applies),
-- driving that change through the openspec lifecycle (groom → implement →
-- verify, which syncs and archives), then committing/pushing/opening a PR
-- and running the convergent PR review loop on it. A completed issue's
-- worktree is torn down — its branch survives — while a failed issue's is
-- kept as the audit trail. The loop stops when the queue holds no eligible
-- issue.
--
-- The issue playbook is agent-free (a claim marker plus earliest-wins
-- read-back); the openspec and pr playbooks own their own convergence and
-- escalation. This script owns only the orchestration between them, so a
-- single issue that fails (a missing human provider, a non-converging
-- review) is logged and the loop moves on — the claim marker stays as the
-- audit trail a human re-queues by hand.
--
-- Ptah scripts take no runtime arguments; the knobs below are hand-edited
-- per environment. The `pi` agent (from the ptah agent registry — the
-- project layer `.ptah/config.toml` or the user layer) must carry the
-- openspec skills and `openspec` must be on PATH for the lifecycle steps,
-- `gh` must be authenticated for the issue/PR steps, and `git` must be on
-- PATH for the worktree steps.

-- This repo is the library itself: there is no generated
-- `luau_packages/ptah_libs` shim, so require the playbook modules directly
-- through the root `.luaurc` alias (the same way the ad-hoc dev workflows
-- under `.ptah/workflows/adhoc/` do).
local issue = require("@ptah_libs/playbooks/issue/playbook")
local openspec = require("@ptah_libs/playbooks/openspec/playbook")
local pr = require("@ptah_libs/playbooks/pr/playbook")
local sessionConfig = require("@ptah_libs/std/session-config")
local worktree = require("@ptah_libs/std/worktree")

-- ---------------------------------------------------------------------------
-- Local config
-- ---------------------------------------------------------------------------

-- The repo-configured queue label: a human's assertion that an issue is ready
-- for development. Required by the issue playbook, which never defaults it.
local QUEUE_LABEL = "ai-r4d"

local MODEL = "zai/glm-5.3-flash"

-- The base every issue's worktree branches from, fetched first so each issue
-- starts from the freshest merged state. A local ref would silently base
-- issues on stale history, and the shared tree's HEAD would stack issue work
-- on whatever branch the checkout happens to be on.
local WORKTREE_REF = "origin/main"
local WORKTREE_FETCH = true

-- Bounded retries for the typed-result hand-offs (resolve change, open PR):
-- agents may ignore the submit tool, so a nil result is designed degradation,
-- not a hard failure, until the attempts are exhausted.
local RESOLVE_ATTEMPTS = 3
local PR_ATTEMPTS = 3

local MAX_REVIEW_ITERATIONS = 10

-- Every session is configured in declared order (see Ptah Playbooks' session
-- config contract). All values here are strings, so no explicit entry
-- annotation is needed.
local workConfig = { { id = "model", value = MODEL } }

local work = ptah.agent("pi")
local judge = ptah.agent("pi")
local reporter = ptah.agent("pi")

local issueOps = issue.new({
	queueLabel = QUEUE_LABEL,
})

-- The openspec and PR playbooks take the working directory as constructor
-- config, so each issue builds its own pair around its worktree instead of
-- sharing a module-level instance.
local function makeOpsx(workingDir: string)
	return openspec.new({
		agent = work,
		judgeAgent = judge,
		sessionConfig = workConfig,
		judgeSessionConfig = workConfig,
		workingDir = workingDir,
	})
end

local function makeReviewLoop(workingDir: string)
	return pr.new({
		agent = work,
		judgeAgent = judge,
		reporterAgent = reporter,
		sessionConfig = workConfig,
		judgeSessionConfig = workConfig,
		reporterSessionConfig = workConfig,
		workingDir = workingDir,
		dryRun = false,
		maxIterations = MAX_REVIEW_ITERATIONS,
	})
end

-- The pickup brief's shape, restated locally: the playbook's exported types
-- ride the generated package shim, which does not expose nested qualified
-- type names, so the structural shape is spelled out here.
type Brief = {
	number: number,
	url: string,
	title: string,
	body: string,
}

-- The provision record's shape, restated locally for the same reason as
-- Brief: the structural shape is easier to name here than the module's
-- exported type.
type Worktree = {
	path: string,
	branch: string,
	ref: string,
}

-- ---------------------------------------------------------------------------
-- The per-issue worktree
-- ---------------------------------------------------------------------------

-- Each issue is implemented in its own worktree on the branch `issue-<n>`,
-- branched off WORKTREE_REF, so agent edits, commits, and pushes never touch
-- the shared checkout (the path is `<sibling of the repo root>/<repo
-- basename>-issue-<n>`, outside any checkout). A rerun adopts the registered
-- worktree or attaches the surviving branch as-is — an interrupted run
-- resumes without anything being reset.
local function prepareWorktree(brief: Brief): Worktree
	local branch = ("issue-%d"):format(brief.number)
	local wt = worktree.provision({
		name = branch,
		ref = WORKTREE_REF,
		branch = branch,
		fetch = WORKTREE_FETCH,
	})
	ptah.log(("factory: issue #%d worktree %s on branch %s"):format(brief.number, wt.path, wt.branch))
	return wt
end

-- ---------------------------------------------------------------------------
-- Issue → change or direct edit
-- ---------------------------------------------------------------------------

-- An agent reads the claimed issue and identifies which *existing* openspec
-- change in `openspec/changes/` should be applied to resolve it. No change is
-- created here. An empty submitted name means no change applies: the issue is
-- a direct edit (see `directEdit` below). The listing is the worktree's, so
-- only changes already merged to WORKTREE_REF are visible; a change that
-- exists only in some unmerged branch resolves as a direct edit.
local function resolveChange(brief: Brief, workingDir: string): string?
	local session = work:session({
		id = ("factory-resolve:%d"):format(brief.number),
		cwd = workingDir,
		resultSchema = {
			type = "object",
			properties = { change = { type = "string" } },
			required = { "change" },
		},
	})
	sessionConfig.apply(session, workConfig)

	local prompt = table.concat({
		("Identify which existing openspec change should be applied to resolve GitHub issue #%d."):format(brief.number),
		"",
		("Title: %s"):format(brief.title),
		("URL: %s"):format(brief.url),
		"",
		"Body:",
		brief.body,
		"",
		"If the issue names an openspec change, use that name. Otherwise list the changes under `openspec/changes/` and pick the one whose scope matches this issue. Do not create a new change and do not implement anything.",
		'Submit that change\'s directory name through this session\'s ptah result tool as { "change": "<kebab-case-name>" }, or an empty string if no change applies and the issue is a direct edit.',
	}, "\n")

	local change: string? = nil
	local resolved = false
	for attempt = 1, RESOLVE_ATTEMPTS do
		local outcome = session:prompt(prompt)
		local result = outcome.result
		if type(result) == "table" and type(result.change) == "string" then
			change = if result.change == "" then nil else result.change
			resolved = true
			break
		end
		ptah.log(("factory: resolver submitted no change name (attempt %d/%d)"):format(attempt, RESOLVE_ATTEMPTS))
	end
	session:close()
	if not resolved then
		error(("factory: could not identify an openspec change for issue #%d"):format(brief.number))
	end
	return change
end

-- No openspec change applies: an agent implements the issue directly in the
-- issue's worktree. The PR review loop that follows is the convergence step.
local function directEdit(brief: Brief, workingDir: string): nil
	local session = work:session({ id = ("factory-direct:%d"):format(brief.number), cwd = workingDir })
	sessionConfig.apply(session, workConfig)

	local prompt = table.concat({
		("Implement GitHub issue #%d directly in this repository. No openspec change applies to it."):format(
			brief.number
		),
		"",
		("Title: %s"):format(brief.title),
		("URL: %s"):format(brief.url),
		"",
		"Body:",
		brief.body,
		"",
		"Make the edits the issue asks for, following the repository's conventions, and run the relevant format and test commands before finishing. Do not create an openspec change.",
	}, "\n")
	session:prompt(prompt)
	session:close()
	return nil
end

-- ---------------------------------------------------------------------------
-- Commit, push, open the PR
-- ---------------------------------------------------------------------------

-- The committer owns the git mechanics (commit, push, `gh pr create`) and
-- returns the PR URL as a typed result. The branch `issue-<n>` is already
-- created and checked out by the worktree step, so the prompt tells it to
-- stay on that branch rather than create or reuse one.
local function openPullRequest(brief: Brief, change: string?, workingDir: string): string
	local session = work:session({
		id = ("factory-pr:%d"):format(brief.number),
		cwd = workingDir,
		resultSchema = {
			type = "object",
			properties = { prUrl = { type = "string" } },
			required = { "prUrl" },
		},
	})
	sessionConfig.apply(session, workConfig)

	local summary = if change ~= nil
		then ("The openspec change `%s` for GitHub issue #%d is implemented, verified, synced, and archived."):format(
			change,
			brief.number
		)
		else ("The changes for GitHub issue #%d are implemented."):format(brief.number)
	local first = table.concat({
		summary,
		("Your working directory is the issue's worktree, with the branch `issue-%d` already checked out. Commit the uncommitted changes (except the .ptah directory) with a Conventional Commits message that references issue #%d, push that branch to the remote, and open a pull request against main using `gh`. Do not create, rename, or switch away from the branch."):format(
			brief.number,
			brief.number
		),
		'Submit the pull request URL through this session\'s ptah result tool as { "prUrl": "https://github.com/..." }.',
	}, "\n")
	local retry =
		'Submit the pull request URL now through this session\'s ptah result tool as { "prUrl": "https://github.com/..." }. If the pull request does not exist yet, create it first.'

	local prUrl: string? = nil
	for attempt = 1, PR_ATTEMPTS do
		local outcome = session:prompt(if attempt == 1 then first else retry)
		local result = outcome.result
		if type(result) == "table" and type(result.prUrl) == "string" and result.prUrl ~= "" then
			prUrl = result.prUrl
			break
		end
		ptah.log(("factory: committer submitted no PR URL (attempt %d/%d)"):format(attempt, PR_ATTEMPTS))
	end
	session:close()
	if prUrl == nil then
		error(("factory: could not open a pull request for issue #%d"):format(brief.number))
	end
	return prUrl
end

-- ---------------------------------------------------------------------------
-- One issue, end to end
-- ---------------------------------------------------------------------------

local function runIssue(brief: Brief): nil
	local wt = prepareWorktree(brief)
	local opsx = makeOpsx(wt.path)
	local reviewLoop = makeReviewLoop(wt.path)

	local change = resolveChange(brief, wt.path)
	if change ~= nil then
		ptah.log(("factory: issue #%d resolved to openspec change `%s`"):format(brief.number, change))
		opsx:groom(change)
		opsx:implement(change)
		opsx:verify(change)
		ptah.log(("factory: change `%s` implemented, verified, synced, and archived"):format(change))
	else
		ptah.log(("factory: issue #%d has no openspec change; implementing directly"):format(brief.number))
		directEdit(brief, wt.path)
	end

	local prUrl = openPullRequest(brief, change, wt.path)
	ptah.log(("factory: issue #%d pull request: %s"):format(brief.number, prUrl))

	local prReview = reviewLoop:review(prUrl)
	ptah.log(("factory: pr review loop %s: %s"):format(prReview.status, prReview.verdict))

	-- Teardown only on the success path: a failed issue (the pcall in the
	-- loop) keeps its worktree as the audit trail, and the branch survives
	-- either way. A dirty refusal is logged, never fatal.
	local removed = worktree.teardown(wt)
	if not removed.ok then
		ptah.log(("factory: issue #%d worktree kept at %s: %s"):format(brief.number, wt.path, tostring(removed.stderr)))
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- The loop
-- ---------------------------------------------------------------------------

while true do
	local picked = issueOps:pickUp()
	if picked.status == "no-eligible-issue" then
		ptah.log(("factory: no eligible issue left (scanned %d); stopping"):format(picked.scanned))
		break
	end

	local brief = picked.brief
	ptah.log(("factory: claimed issue #%d — %s"):format(brief.number, brief.title))

	-- Per-issue error boundary: a failed issue is logged and left claimed
	-- (the marker is the audit trail), and the loop advances to the next one.
	local ok, failure = pcall(runIssue, brief)
	if not ok then
		ptah.log(("factory: issue #%d failed: %s"):format(brief.number, tostring(failure)))
	end
end
