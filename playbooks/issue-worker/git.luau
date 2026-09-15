--!strict
-- issueWorker's private git mechanics: repo root discovery, the
-- per-issue worktree (create-or-reuse) on the issue branch from
-- `origin/<baseBranch>`, the commits-ahead count the delivery contract
-- re-checks, and the openspec change-directory guard. Kept private to
-- the playbook: git worktrees have one consumer today, so the
-- mechanics are promoted to `std` only when a second playbook needs
-- them verbatim.

local shell = require("../../std/shell")

local M = {}

-- The repository root of the invocation directory. A run must happen
-- inside the repository; anything else is a script error.
function M.repoRoot(): string
	local result = ptah.exec("git rev-parse --show-toplevel")
	if result.exitCode ~= 0 then
		error("issue-worker must run inside the repository: " .. shell.trim(result.stderr), 0)
	end
	return shell.trim(result.stdout)
end

-- Resolve the per-issue worktree path. `worktreeDir` is relative to the
-- repository root by default (`"tmp"`), and the result is always an
-- absolute path so no exec ever runs with a relative working directory.
function M.path(repoRoot: string, worktreeDir: string, branch: string): string
	local base = if string.sub(worktreeDir, 1, 1) == "/" then worktreeDir else repoRoot .. "/" .. worktreeDir
	return base .. "/" .. branch
end

-- Create the worktree on `branch` from the freshly fetched
-- `origin/<baseBranch>`, or reuse an existing one (crash recovery: a
-- previous run may have left it behind with commits worth keeping). An
-- existing worktree on a different branch is a hard error — reusing it
-- would deliver the wrong work.
function M.ensure(repoRoot: string, worktreeDir: string, baseBranch: string, branch: string): string
	local dir = M.path(repoRoot, worktreeDir, branch)
	shell.mustRun(("git -C %s fetch origin %s"):format(shell.quote(repoRoot), shell.quote(baseBranch)))
	if shell.succeeds(("test -d %s"):format(shell.quote(dir))) then
		local current = shell.mustRun(("git -C %s branch --show-current"):format(shell.quote(dir)))
		if current ~= branch then
			error(("worktree %s is on branch %s, expected %s"):format(dir, current, branch), 0)
		end
		ptah.log(("issue-worker: reusing worktree %s"):format(dir))
		return dir
	end
	shell.mustRun(
		("git -C %s worktree add %s -b %s origin/%s"):format(
			shell.quote(repoRoot),
			shell.quote(dir),
			shell.quote(branch),
			shell.quote(baseBranch)
		)
	)
	return dir
end

-- Number of commits on `branch` ahead of `origin/<baseBranch>`, counted
-- in the worktree. The delivery contract re-checks this deterministically
-- instead of trusting the delivery session's prose.
function M.commitsAhead(dir: string, baseBranch: string, branch: string): number
	local out = shell.mustRun(
		("git -C %s rev-list --count origin/%s..%s"):format(shell.quote(dir), shell.quote(baseBranch), shell.quote(branch))
	)
	local count = tonumber(out)
	if count == nil then
		error(("issue-worker: could not parse commits-ahead count for %s: %s"):format(branch, out), 0)
	end
	return count
end

-- Guard that a triage-authored openspec change actually exists in the
-- worktree before the openspec playbook loops run against it.
function M.requireChangeDir(dir: string, changeName: string): ()
	if not shell.succeeds(("test -d %s/openspec/changes/%s"):format(shell.quote(dir), shell.quote(changeName))) then
		error(
			("issue-worker: triage reported openspec change '%s' but openspec/changes/%s does not exist in the worktree"):format(
				changeName,
				changeName
			),
			0
		)
	end
end

return M
