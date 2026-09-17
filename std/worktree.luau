--!strict
-- Worktree lifecycle (stdlib): provision and tear down git linked
-- worktrees through ptah's exec, so a consumer shim isolates per-item
-- runs in their own checkout without managing git state by hand.
--
-- Policy as parameters, with safe defaults: `provision` adopts an
-- existing worktree as-is, fast-forwards-or-fails an existing branch
-- against its remote counterpart, and never resets or renames;
-- `teardown` refuses a dirty worktree by default and never touches
-- branches (unpushed commits survive on the local branch). One path
-- identity rules a provision run: an explicit relative parent resolves
-- from the selected repository root, the target collapses to its
-- canonical physical absolute path before any lookup or mutation, and
-- after creation git's registered path is authoritative.
--
-- Failure is asymmetric on purpose: `provision` raises carrying git's
-- stderr (a failed provision means the run cannot proceed, pcall-able);
-- `teardown` returns its outcome as data — a dirty refusal is the
-- expected post-crash outcome, and it happens after a possibly-converged
-- loop, so the caller logs it rather than failing the run.
--
-- Environment: `git` on PATH (declared, not bundled), like the GitHub
-- transport's `gh`. The mechanism accepts no agent handles and no
-- configuration table.

export type ProvisionOptions = {
	-- Identity of this worktree within its repository; the path is
	-- derived from it (`<parent>/<repo-basename>-<name>`).
	name: string,
	-- Start point. Required and never defaulted: git's own default is
	-- the shared tree's HEAD, the bug class this mechanism removes.
	ref: string,
	-- Branch name. Defaults to the ref's short name when the ref is a
	-- remote-tracking ref (`origin/x` -> `x`); pass one explicitly when
	-- the branch must differ from the ref (`ref = "origin/main"`,
	-- `branch = "openspec/add-auth"`).
	branch: string?,
	-- Fetch the ref's remote (a plain fetch, no refspec) before
	-- resolution.
	fetch: boolean?,
	-- Repository to operate on. Defaults to the invocation directory's
	-- repository (`git rev-parse --show-toplevel`).
	repo: string?,
	-- Directory that will hold the worktree. Defaults to the repository
	-- root's sibling, so a worktree never lives inside a checkout of the
	-- repository. A relative parent resolves against the selected
	-- repository root — not the invocation directory — matching where
	-- git itself puts the worktree for `git -C <root> worktree add`.
	parent: string?,
}

-- The provision record: the canonical physical absolute worktree path
-- (after creation, git's exact registered path key), the branch attached
-- to it, and the ref it was resolved from.
export type Worktree = {
	path: string,
	branch: string,
	ref: string,
}

export type TeardownOptions = {
	-- Remove even a dirty worktree, discarding uncommitted changes
	-- (branches are still never touched).
	force: boolean?,
}

export type TeardownOutcome = {
	ok: boolean,
	-- git's message when the removal failed (nil on success).
	stderr: string?,
}

local function trim(s: string): string
	local trimmed = (s:gsub("^%s+", ""))
	return (trimmed:gsub("%s+$", ""))
end

-- POSIX sh single-quoting: wrap in single quotes and escape embedded
-- single quotes as '\'' (close, escaped quote, reopen).
local function quote(arg: string): string
	return "'" .. (arg:gsub("'", "'\\''")) .. "'"
end

-- Run git, returning the raw outcome (never raising). `repo` nil runs in
-- the invocation directory. Default `stdout` is trimmed text, as callers
-- have always seen; `opts.rawStdout` keeps git's stdout byte-exact for
-- formats whose path bytes and record delimiters trimming would corrupt
-- (the worktree inventory). `stderr` is always trimmed text.
type GitOptions = {
	rawStdout: boolean?,
}
local function execGit(repo: string?, args: { string }, opts: GitOptions?): { exitCode: number, stdout: string, stderr: string }
	local command = "git"
	if repo ~= nil then
		command ..= " -C " .. quote(repo)
	end
	for _, arg in ipairs(args) do
		command ..= " " .. quote(arg)
	end
	local result = ptah.exec(command)
	local stdout = if opts ~= nil and opts.rawStdout == true then result.stdout else trim(result.stdout)
	return { exitCode = result.exitCode, stdout = stdout, stderr = trim(result.stderr) }
end

-- Run git, raising git's stderr on failure. A provision that cannot run
-- its git command has nowhere to go, so this is the loud form.
local function git(repo: string?, args: { string }, opts: GitOptions?): string
	local result = execGit(repo, args, opts)
	if result.exitCode ~= 0 then
		local detail = if result.stderr ~= "" then result.stderr else result.stdout
		error(`worktree: git {table.concat(args, " ")} failed: {detail}`)
	end
	return result.stdout
end

local function parentOf(path: string): string
	return string.match(path, "^(.*)/[^/]+$") or "/"
end

local function basename(path: string): string
	return string.match(path, "([^/]+)$") or path
end

-- Resolve the repository root: the ref/default for every other git call.
local function repoRoot(repo: string?): string
	local root = git(repo, { "rev-parse", "--show-toplevel" })
	if root == "" then
		error("worktree: could not determine the repository root (is the invocation directory inside a git repository?)")
	end
	return root
end

-- The configured remote names, so `openspec/add-auth` (a local branch)
-- is not mistaken for `openspec/add-auth` (a remote-tracking ref).
local function configuredRemotes(root: string): { [string]: boolean }
	local remotes: { [string]: boolean } = {}
	for name in string.gmatch(git(root, { "remote" }), "[^\n]+") do
		remotes[name] = true
	end
	return remotes
end

-- The remote part of a remote-tracking ref (`origin/x` -> `origin`), or
-- nil when the ref is local. Guards slashed local branch names by
-- consulting the configured remotes, not the slash alone.
local function remoteOf(remotes: { [string]: boolean }, ref: string): string?
	local first = string.match(ref, "^([^/]+)/.+$")
	if first ~= nil and remotes[first] then
		return first
	end
	return nil
end

-- Worktree inventory, parsed losslessly from NUL-delimited porcelain
-- (`--porcelain -z`, raw stdout): fields are NUL-terminated and unusual
-- paths are never quoted, so spaces, non-ASCII characters, quoting
-- characters, newlines, and the record delimiters themselves survive
-- exactly. A record starts at each `worktree <path>` field; a following
-- `branch refs/heads/<name>` field names its branch; empty separators
-- and unrelated fields are ignored; a record without a branch field is
-- a detached worktree.
local function registeredWorktrees(root: string): { paths: { [string]: boolean }, branches: { [string]: string } }
	local output = git(root, { "worktree", "list", "--porcelain", "-z" }, { rawStdout = true })
	local paths: { [string]: boolean } = {}
	local branches: { [string]: string } = {}
	local current: string? = nil
	for field in string.gmatch(output, "[^%z]+") do
		local wt = string.match(field, "^worktree (.*)$")
		if wt ~= nil then
			current = wt
			paths[wt] = true
		else
			local branch = string.match(field, "^branch refs/heads/(.*)$")
			if branch ~= nil and current ~= nil then
				branches[current] = branch
			end
		end
	end
	return { paths = paths, branches = branches }
end

local function branchExists(root: string, branch: string): boolean
	return execGit(root, { "show-ref", "--verify", "--quiet", `refs/heads/{branch}` }).exitCode == 0
end

local function pathExists(path: string): boolean
	return ptah.exec("test -e " .. quote(path)).exitCode == 0
end

-- Resolve `dir` to its physical absolute directory: symlink components
-- collapse (`pwd -P`), relative input resolves from the caller's chosen
-- coordinate system, and a missing directory returns nil for the caller
-- to fail loudly on. POSIX shell built-ins only (`test`, `cd`, `pwd`);
-- every dynamic value is single-quoted.
local function physicalDir(dir: string): string?
	local result = ptah.exec(`if test -d {quote(dir)}; then cd {quote(dir)} && pwd -P; else exit 64; fi`)
	if result.exitCode ~= 0 then
		return nil
	end
	return trim(result.stdout)
end

-- Provision a worktree, resolving in the order the spec fixes. Returns
-- the record on success; raises git's stderr on any failure.
local function provision(options: ProvisionOptions): Worktree
	-- The analyzer already requires these; the guards keep an untyped
	-- caller's nil from becoming a confusing git failure.
	if (options.ref :: string?) == nil then
		error("worktree: ref is required (there is no default start point, and never the shared tree's HEAD)")
	end
	if (options.name :: string?) == nil then
		error("worktree: name is required")
	end

	local root = repoRoot(options.repo)
	local remotes = configuredRemotes(root)
	local remote = remoteOf(remotes, options.ref)
	local short = if remote ~= nil then string.sub(options.ref, #remote + 2) else options.ref
	local branch = if options.branch ~= nil then options.branch else short

	-- One path identity for the whole operation. An explicit relative
	-- parent resolves against the selected repository root — the same
	-- place `git -C <root> worktree add` puts the target — and the parent
	-- then collapses to its physical absolute directory, so symlink
	-- aliases and the invocation directory cannot split inventory lookup,
	-- existence checks, git arguments, diagnostics, and the returned
	-- path onto different coordinate systems. A missing parent fails
	-- loudly here; nothing creates it.
	local explicitParent = options.parent
	local parent: string
	if explicitParent == nil then
		parent = parentOf(root)
	elseif string.match(explicitParent, "^/") == nil then
		parent = `{root}/{explicitParent}`
	else
		parent = explicitParent
	end
	local physicalParent = physicalDir(parent)
	if physicalParent == nil then
		error(`worktree: parent directory {parent} does not exist or is not a directory`)
	end
	local path = `{physicalParent}/{basename(root)}-{options.name}`

	if options.fetch == true and remote ~= nil then
		git(root, { "fetch", remote })
	end

	local registered = registeredWorktrees(root)
	if registered.paths[path] then
		-- Adopt as-is: no reset, no re-add, so an interrupted run resumes.
		local existing = registered.branches[path]
		if existing == branch then
			return { path = path, branch = branch, ref = options.ref }
		end
		local actual = if existing ~= nil then `branch {existing}` else "a detached HEAD"
		error(`worktree: {path} is a registered worktree on {actual}, not branch {branch}`)
	end

	if pathExists(path) then
		error(`worktree: {path} exists but is not a registered worktree; refusing to touch it`)
	end

	if branchExists(root, branch) then
		-- The resume case: a previous teardown kept the branch. Ref is
		-- the branch's remote-tracking counterpart -> fast-forward or
		-- fail loudly; anything else -> attach as-is and keep its
		-- commits.
		if remote ~= nil and short == branch then
			git(root, { "fetch", remote, `{branch}:{branch}` })
		end
		git(root, { "worktree", "add", path, branch })
	else
		git(root, { "worktree", "add", "-b", branch, path, options.ref })
	end

	-- Git is the final authority on identity: re-read the inventory,
	-- require the canonical target to be registered on the requested
	-- branch, and return that exact path key. An unexpected mismatch
	-- leaves the (healthy) worktree in place for inspection — never an
	-- automatic removal.
	local readback = registeredWorktrees(root)
	if not readback.paths[path] or readback.branches[path] ~= branch then
		error(`worktree: {path} was created but is not registered on branch {branch}; leaving it in place for manual inspection`)
	end

	return { path = path, branch = branch, ref = options.ref }
end

-- The repository a worktree belongs to, discovered from the worktree
-- itself so teardown needs only `path`. Nil falls back to the invocation
-- directory.
local function worktreeRepo(path: string): string?
	local result = execGit(nil, { "-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir" })
	if result.exitCode ~= 0 or result.stdout == "" then
		return nil
	end
	return parentOf(result.stdout)
end

-- Tear a provisioned worktree down: refuse-dirty by default, remove and
-- prune otherwise, never a branch. Outcome as data — never raises.
local function teardown(worktree: { path: string }, options: TeardownOptions?): TeardownOutcome
	local opts: TeardownOptions = if options ~= nil then options else {}
	local repo = worktreeRepo(worktree.path)
	local args = { "worktree", "remove" }
	if opts.force == true then
		table.insert(args, "--force")
	end
	table.insert(args, worktree.path)

	local result = execGit(repo, args)
	if result.exitCode ~= 0 then
		return { ok = false, stderr = if result.stderr ~= "" then result.stderr else result.stdout }
	end
	-- Best-effort cleanup of the registration the removal just retired.
	execGit(repo, { "worktree", "prune" })
	return { ok = true }
end

return {
	provision = provision,
	teardown = teardown,
}
