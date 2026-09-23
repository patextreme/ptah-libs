--!strict
-- Worktree lifecycle (stdlib): provision and tear down git linked
-- worktrees through ptah's exec, so a consumer shim isolates per-item
-- runs in their own checkout without managing git state by hand.
--
-- Policy as parameters, with safe defaults: `provision` adopts an
-- existing worktree as-is, prunes a stale registration (one whose
-- directory a `git clean -ffdx` or a manual `rm` deleted) and
-- re-creates the worktree — or raises when the registration survives
-- the prune (a locked worktree; unlocking is never provision's act) —
-- resolves a requested branch already held by another registration
-- (a live occupant raises naming both paths and is left untouched;
-- a stale occupant is pruned and provisioned; a locked stale occupant
-- raises, never unlocked or removed), fast-forwards-or-fails an
-- existing branch against its remote counterpart, and never resets or
-- renames; `teardown` refuses a dirty worktree by default and never
-- touches branches (unpushed commits survive on the local branch).
-- One path identity rules a provision run: an explicit relative
-- parent resolves from the selected repository root, the target
-- collapses to its canonical physical absolute path before any lookup
-- or mutation, and after creation git's registered path is
-- authoritative. The one deliberate widening: the stale-registration
-- self-heal covers the registration that holds the requested branch,
-- not only the target path, and `git worktree prune` is global, so
-- resolving it may retire another path's stale registration (dead
-- state no owner can use; git offers no path-scoped prune).
--
-- Worktrees default under the repository's own `.ptah/worktree/` — one
-- conventional home for everything ptah-owned in a consumer repo. A
-- worktree inside the checkout is an accepted, documented trade-off:
-- `git clean -ffdx` in the shared checkout deletes nested worktree
-- directories (a plain `git clean -fdx` skips nested repositories;
-- branches survive in the shared object store; uncommitted state does
-- not; the next provision prunes the stale registration and re-creates
-- the worktree — a locked registration raises instead), and a consumer
-- who cannot accept that passes `parent` explicitly to place worktrees
-- outside every checkout.
--
-- Failure is asymmetric on purpose: `provision` raises carrying git's
-- stderr (a failed provision means the run cannot proceed, pcall-able);
-- `teardown` returns its outcome as data — a dirty refusal is the
-- expected post-crash outcome, and it happens after a possibly-converged
-- loop, so the caller logs it rather than failing the run.
--
-- `liveOccupant` is the one introspection export: it reports the path
-- of the registered worktree currently holding a branch when that
-- worktree's directory exists, and nil when no registration holds the
-- branch or the only registration is stale (a stale registration stays
-- provision's prune-self-heal business). No policy, no side effects —
-- it reports; it never removes — and provision's live-occupant raise
-- is unchanged by it.
--
-- Environment: `git` on PATH (declared, not bundled), like the GitHub
-- transport's `gh`, and a git-ignored `.ptah/worktree/` under the
-- repository root — without the ignore rule every default worktree is
-- untracked noise in the shared checkout's `git status`. The mechanism
-- accepts no agent handles and no configuration table.

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
	-- Directory that will hold the worktree. Defaults to
	-- `<repository root>/.ptah/worktree`, so worktrees live under the
	-- repository's own ptah directory; pass a directory outside any
	-- checkout when `git clean -ffdx` over nested worktrees is
	-- unacceptable (branches survive a clean; uncommitted state does
	-- not). A missing parent directory, intermediate directories
	-- included, is created. A relative parent resolves against the
	-- selected repository root — not the invocation directory —
	-- matching where git itself puts the worktree for
	-- `git -C <root> worktree add`.
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

-- The worktree registration currently attached to `branch`, from the
-- already-parsed inventory (`branches` maps path -> branch); nil when
-- no registration holds it. A pure lookup over the parsed association
-- — no git call — so the caller can re-run it against a re-read
-- inventory after a prune. Git ties a branch to at most one
-- registration, so the scan finds at most one occupant.
local function branchOccupant(registered: { paths: { [string]: boolean }, branches: { [string]: string } }, branch: string): string?
	for occupant, held in pairs(registered.branches) do
		if held == branch then
			return occupant
		end
	end
	return nil
end

local function pathExists(path: string): boolean
	return ptah.exec("test -e " .. quote(path)).exitCode == 0
end

-- Resolve `dir` to its physical absolute directory: symlink components
-- collapse (`pwd -P`), relative input resolves from the caller's chosen
-- coordinate system, and a missing directory returns nil for the caller
-- to fail loudly on. POSIX shell built-ins only (`test`, `cd`, `pwd`);
-- every dynamic value is single-quoted. Exactly pwd's one trailing
-- newline is stripped — never `trim()`: a trailing whitespace byte can
-- belong to the path itself (`ts ` is a legal POSIX directory name), and
-- stripping it would re-key the whole provision onto a mangled location
-- that the post-create readback cannot catch (git registers the path it
-- was handed). Every other byte, including embedded and trailing
-- whitespace inside the path, survives exactly, like the inventory.
local function physicalDir(dir: string): string?
	local result = ptah.exec(`if test -d {quote(dir)}; then cd {quote(dir)} && pwd -P; else exit 64; fi`)
	if result.exitCode ~= 0 then
		return nil
	end
	return (result.stdout:gsub("\n$", ""))
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
	-- path onto different coordinate systems.
	local explicitParent = options.parent
	local parent: string
	if explicitParent == nil then
		parent = `{root}/.ptah/worktree`
	elseif string.match(explicitParent, "^/") == nil then
		parent = `{root}/{explicitParent}`
	else
		parent = explicitParent
	end

	-- The library owns parent creation: git's native creation of missing
	-- parents for `worktree add` is version-dependent and declared
	-- nowhere here, so the SHALL holds by this mkdir, not by whatever the
	-- local git happens to do. Idempotent on an existing parent; a fresh
	-- path is the only case that creates. It precedes the physical
	-- collapse because `pwd -P` needs the directory to exist.
	local made = ptah.exec("mkdir -p " .. quote(parent))
	if made.exitCode ~= 0 then
		local detail = if made.stderr ~= "" then made.stderr else made.stdout
		error(`worktree: mkdir -p {parent} failed: {detail}`)
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
	if registered.paths[path] and not pathExists(path) then
		-- Stale registration: a `git clean -ffdx` or a manual `rm`
		-- deleted the worktree directory while the registration
		-- survived (git marks it prunable). Adopting as-is would hand
		-- back a path that no longer exists and would never self-heal,
		-- so prune the stale registration and fall through — the
		-- branch survives the deletion, and the checks below re-create
		-- the worktree at the same path.
		git(root, { "worktree", "prune" })
		registered = registeredWorktrees(root)
		if registered.paths[path] then
			-- The prune kept it: a locked stale registration (git skips
			-- locked worktrees so one on an unmounted device or network
			-- share keeps its admin files). Raising beats adopting a
			-- nonexistent path, and unlocking is the registration
			-- owner's decision, never provision's.
			error(`worktree: {path} is registered but its directory is gone and the registration survived prune (a locked worktree?); unlock it or run git worktree prune by hand`)
		end
	end

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

	-- Branch-occupant resolution, ahead of every command git refuses
	-- for an occupied branch (the fast-forward fetch as well as the
	-- attach). A live occupant is another owner's worktree: raise
	-- naming both paths, touch nothing. A stale occupant (its
	-- directory is gone, the registration survived) self-heals through
	-- the same global prune the stale-target case uses; a survivor is
	-- a locked registration and raises — never unlocked, never removed.
	local occupant = branchOccupant(registered, branch)
	if occupant ~= nil and not pathExists(occupant) then
		git(root, { "worktree", "prune" })
		registered = registeredWorktrees(root)
		occupant = branchOccupant(registered, branch)
	end
	if occupant ~= nil then
		if pathExists(occupant) then
			error(`worktree: branch {branch} is already checked out at {occupant}; remove that worktree before provisioning {path}`)
		end
		error(`worktree: branch {branch} is held by a stale registration at {occupant} whose directory is gone and the registration survived prune (a locked worktree?); unlock it or run git worktree prune by hand`)
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

-- The occupant introspection options: the branch to look up, and the
-- repository to resolve it against (defaulting to the invocation
-- directory's repository, exactly like provision's `repo`).
export type LiveOccupantOptions = {
	-- The branch whose live occupant is reported.
	branch: string,
	-- Repository to operate on. Defaults to the invocation directory's
	-- repository (`git rev-parse --show-toplevel`).
	repo: string?,
}

-- Report the live occupant of `branch`: the path of the registered
-- worktree currently attached to it, when that worktree's directory
-- exists. Nil when no registration holds the branch, and nil when the
-- only registration is stale (its directory is gone — stale state
-- remains provision's prune-self-heal business). Pure introspection:
-- no prune, no creation, no removal, no fetch, and no branch
-- inspection beyond the inventory provision already parses. It carries
-- no policy — it reports; it never removes — and provision's
-- live-occupant raise is unchanged by it.
local function liveOccupant(options: LiveOccupantOptions): string?
	-- The analyzer already requires this; the guard keeps an untyped
	-- caller's nil from becoming a confusing git failure.
	if (options.branch :: string?) == nil then
		error("worktree: branch is required")
	end
	local root = repoRoot(options.repo)
	local occupant = branchOccupant(registeredWorktrees(root), options.branch)
	if occupant ~= nil and pathExists(occupant) then
		return occupant
	end
	return nil
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
	liveOccupant = liveOccupant,
}
