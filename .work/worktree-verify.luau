--!strict
-- Verification harness for the worktree-default-under-ptah change
-- (uncommitted `.work/` scratch): ports the worktree-aware-playbooks
-- change's inline resolution/teardown cases — fresh provision,
-- adopt-as-is, fast-forward, diverge-errors; teardown clean, dirty
-- refusal, branch survival — all passing `parent` explicitly (expected
-- unaffected), and adds the default-parent case: provision without
-- `parent` against the throwaway repo lands at
-- `<MAIN>/.ptah/worktree/main-<name>` with the parent auto-created, and
-- adoption behaves as before; plus the stale-registration case: the
-- forced clean runs while the worktree is still registered (teardown
-- moved after it), the registration's survival is asserted, and the
-- next provision prunes the stale registration and re-creates the
-- worktree at the same path from the surviving branch; plus the
-- locked-stale case: a locked registration survives prune, so
-- provision raises instead of adopting the nonexistent path; plus the
-- branch-occupant cases: a branch attached to a different registered
-- worktree is resolved before any attach — a live occupant raises
-- naming both the occupant and the target path and is left untouched;
-- a stale occupant (directory deleted out-of-band, registration
-- surviving) is pruned and the worktree is provisioned at the target
-- path from the surviving branch; a locked stale occupant raises with
-- the lock-aware wording and its registration survives, never
-- unlocked or removed.
--
-- Everything runs against a throwaway local git setup (a bare `origin`,
-- a `main` clone, an `updater` clone for advancing the remote), removed
-- again whether the checks pass or fail.

local worktree = require("../std/worktree")

export type ExecResult = { exitCode: number, stdout: string, stderr: string }

local function trim(s: string): string
	local t = (s:gsub("^%s+", ""))
	return (t:gsub("%s+$", ""))
end

local function quote(arg: string): string
	return "'" .. (arg:gsub("'", "'\\''")) .. "'"
end

-- Run sh, raising on any nonzero exit (setup has nowhere to go).
local function sh(cmd: string): string
	local result: ExecResult = ptah.exec(cmd)
	if result.exitCode ~= 0 then
		local detail = if result.stderr ~= "" then result.stderr else result.stdout
		error("worktree-verify: `" .. cmd .. "` failed: " .. detail, 0)
	end
	return trim(result.stdout)
end

local function expect(condition: boolean, message: string)
	if not condition then
		error(`worktree-verify: {message}`, 0)
	end
end

local function runAll(base: string)
	local MAIN = `{base}/main`
	local UPDATER = `{base}/updater`
	local WTS = `{base}/wts` -- explicit parent, outside any checkout

	-- -----------------------------------------------------------------
	-- Throwaway git setup: bare origin, a `main` clone, initial commit.
	-- -----------------------------------------------------------------
	sh(`git init --bare -b main {quote(`{base}/origin.git`)}`)
	sh(`git clone {quote(`{base}/origin.git`)} {quote(MAIN)}`)
	sh(`git -C {quote(MAIN)} config user.email verify@example.com`)
	sh(`git -C {quote(MAIN)} config user.name verify`)
	sh(`git -C {quote(MAIN)} commit --allow-empty -m init`)
	sh(`git -C {quote(MAIN)} push -u origin main`)

	-- -----------------------------------------------------------------
	-- Case: fresh provision (explicit parent — unaffected by the change)
	-- -----------------------------------------------------------------
	local fresh = worktree.provision({
		repo = MAIN,
		name = "fresh",
		ref = "origin/main",
		branch = "feature-1",
		parent = WTS,
	})
	expect(fresh.path == `{WTS}/main-fresh`, `fresh path is {fresh.path}, expected {WTS}/main-fresh`)
	expect(fresh.branch == "feature-1", "fresh branch is feature-1")
	expect(sh(`git -C {quote(fresh.path)} rev-parse HEAD`) == sh(`git -C {quote(MAIN)} rev-parse origin/main`), "fresh branch was created from the ref")
	expect(sh(`git -C {quote(fresh.path)} config branch.feature-1.remote`) == "origin", "fresh branch has upstream origin")
	expect(sh(`git -C {quote(fresh.path)} config branch.feature-1.merge`) == "refs/heads/main", "upstream auto-set to the remote-tracking ref it was created from")
	-- Pushable: commit and push the intended branch.
	sh(`git -C {quote(fresh.path)} commit --allow-empty -m "fresh work"`)
	sh(`git -C {quote(fresh.path)} push origin feature-1`)
	ptah.log("ok: fresh provision (explicit parent) creates a pushable branch")

	-- -----------------------------------------------------------------
	-- Case: adopt-as-is (explicit parent — unaffected by the change)
	-- -----------------------------------------------------------------
	-- Adopt-as-is must keep unpushed work: leave an unpushed commit, then
	-- re-provision.
	sh(`git -C {quote(fresh.path)} commit --allow-empty -m "unpushed work"`)
	local unpushedHead = sh(`git -C {quote(fresh.path)} rev-parse HEAD`)
	local adopted = worktree.provision({
		repo = MAIN,
		name = "fresh",
		ref = "origin/feature-1",
		branch = "feature-1",
		parent = WTS,
	})
	expect(adopted.path == fresh.path, "adopted path is the same")
	expect(adopted.branch == "feature-1", "adopted branch is feature-1")
	expect(sh(`git -C {quote(adopted.path)} rev-parse HEAD`) == unpushedHead, "adoption kept the unpushed commit (no reset)")
	-- Teardown (setup for the diverge case; branch survives unpushed work).
	local removed = worktree.teardown(adopted)
	expect(removed.ok, `clean teardown of the adopted worktree succeeded: {tostring(removed.stderr)}`)
	ptah.log("ok: existing worktree adopted as-is, no reset")

	-- -----------------------------------------------------------------
	-- Case: diverged branch errors loudly (explicit parent — unaffected)
	-- -----------------------------------------------------------------
	sh(`git clone {quote(`{base}/origin.git`)} {quote(UPDATER)}`)
	sh(`git -C {quote(UPDATER)} config user.email verify@example.com`)
	sh(`git -C {quote(UPDATER)} config user.name verify`)
	sh(`git -C {quote(UPDATER)} fetch origin feature-1`)
	sh(`git -C {quote(UPDATER)} checkout feature-1`)
	sh(`git -C {quote(UPDATER)} commit --allow-empty -m "remote moves on"`)
	sh(`git -C {quote(UPDATER)} push`)
	local divergedOk, divergedErr = pcall(function()
		return worktree.provision({
			repo = MAIN,
			name = "fresh",
			ref = "origin/feature-1",
			branch = "feature-1",
			parent = WTS,
		})
	end)
	expect(divergedOk == false, `diverged provision raised (got {tostring(divergedErr)})`)
	expect(
		string.find(tostring(divergedErr), "failed", 1, true) ~= nil,
		`diverged error carries the git failure: {tostring(divergedErr)}`
	)
	expect(
		string.find(sh(`git -C {quote(MAIN)} worktree list --porcelain`), `{WTS}/main-fresh`, 1, true) == nil,
		"no worktree was registered by the failed provision"
	)
	ptah.log("ok: diverged branch errors loudly")

	-- -----------------------------------------------------------------
	-- Case: fast-forward-or-fail against the remote counterpart
	-- (explicit parent — unaffected by the change)
	-- -----------------------------------------------------------------
	local ff = worktree.provision({
		repo = MAIN,
		name = "ff",
		ref = "origin/main",
		branch = "feature-2",
		parent = WTS,
	})
	sh(`git -C {quote(ff.path)} commit --allow-empty -m "ff work"`)
	sh(`git -C {quote(ff.path)} push origin feature-2`)
	expect(worktree.teardown(ff).ok, "teardown before the ff rerun")
	sh(`git -C {quote(UPDATER)} fetch origin feature-2`)
	sh(`git -C {quote(UPDATER)} checkout feature-2`)
	sh(`git -C {quote(UPDATER)} commit --allow-empty -m "remote advances feature-2"`)
	sh(`git -C {quote(UPDATER)} push`)
	local behind = sh(`git -C {quote(MAIN)} rev-parse feature-2`)
	local ffed = worktree.provision({
		repo = MAIN,
		name = "ff",
		ref = "origin/feature-2",
		branch = "feature-2",
		parent = WTS,
	})
	expect(ffed.path == ff.path, "ff rerun attaches the same path")
	local remoteHead = sh(`git -C {quote(MAIN)} rev-parse origin/feature-2`)
	expect(sh(`git -C {quote(ffed.path)} rev-parse HEAD`) == remoteHead, "branch fast-forwarded to the remote head")
	expect(behind ~= remoteHead, "the branch actually moved (was behind)")
	ptah.log("ok: existing branch fast-forwards against its remote counterpart")

	-- -----------------------------------------------------------------
	-- Case: teardown clean (explicit parent — unaffected by the change)
	-- -----------------------------------------------------------------
	local cleanOut = worktree.teardown(ffed)
	expect(cleanOut.ok, `clean teardown reports ok: {tostring(cleanOut.stderr)}`)
	expect(cleanOut.stderr == nil, "clean teardown carries no stderr")
	expect(sh(`test -e {quote(ffed.path)}; echo $?`) == "1", "worktree directory removed")
	expect(
		string.find(sh(`git -C {quote(MAIN)} worktree list --porcelain`), `{WTS}/main-ff`, 1, true) == nil,
		"worktree pruned from the registration"
	)
	ptah.log("ok: clean teardown removes and prunes")

	-- -----------------------------------------------------------------
	-- Case: dirty refusal is data, then branch survival (explicit parent)
	-- -----------------------------------------------------------------
	local dirty = worktree.provision({
		repo = MAIN,
		name = "dirty",
		ref = "origin/main",
		branch = "feature-3",
		parent = WTS,
	})
	sh(`echo noise > {quote(`{dirty.path}/noise.txt`)}`)
	local refused = worktree.teardown(dirty)
	expect(refused.ok == false, "dirty teardown refuses")
	expect(refused.stderr ~= nil and refused.stderr ~= "", "dirty refusal carries git's message")
	expect(sh(`test -e {quote(dirty.path)}; echo $?`) == "0", "refused worktree left in place")
	-- Commit the dirt: teardown then succeeds and the branch + its
	-- unpushed commit survive.
	sh(`git -C {quote(dirty.path)} add -A`)
	sh(`git -C {quote(dirty.path)} commit -m "dirty work"`)
	local dirtyHead = sh(`git -C {quote(dirty.path)} rev-parse HEAD`)
	local survived = worktree.teardown(dirty)
	expect(survived.ok, `teardown after committing the dirt: {tostring(survived.stderr)}`)
	expect(
		sh(`git -C {quote(MAIN)} show-ref --verify --quiet refs/heads/feature-3; echo $?`) == "0",
		"branch survives teardown"
	)
	expect(sh(`git -C {quote(MAIN)} rev-parse feature-3`) == dirtyHead, "branch keeps its unpushed commit")
	ptah.log("ok: dirty refusal is data; branch survives teardown")

	-- -----------------------------------------------------------------
	-- Case: default parent — provision without `parent` against MAIN
	-- -----------------------------------------------------------------
	expect(sh(`test -e {quote(`{MAIN}/.ptah/worktree`)}; echo $?`) == "1", ".ptah/worktree absent before the default provision")
	local auto = worktree.provision({
		repo = MAIN,
		name = "auto-1",
		ref = "origin/main",
		branch = "auto-1",
	})
	expect(
		auto.path == `{MAIN}/.ptah/worktree/main-auto-1`,
		`default path is {auto.path}, expected {MAIN}/.ptah/worktree/main-auto-1`
	)
	expect(
		sh(`test -d {quote(`{MAIN}/.ptah/worktree`)}; echo $?`) == "0",
		"parent directory auto-created"
	)
	-- Adoption behaves as before at the default location: commit, re-provision.
	sh(`git -C {quote(auto.path)} commit --allow-empty -m "auto work"`)
	local autoHead = sh(`git -C {quote(auto.path)} rev-parse HEAD`)
	local autoAdopted = worktree.provision({
		repo = MAIN,
		name = "auto-1",
		ref = "origin/main",
		branch = "auto-1",
	})
	expect(autoAdopted.path == auto.path, "default-parent rerun adopts the same path")
	expect(sh(`git -C {quote(autoAdopted.path)} rev-parse HEAD`) == autoHead, "default-parent adoption left HEAD untouched")
	ptah.log("ok: default parent is <MAIN>/.ptah/worktree, auto-created; adoption behaves as before")

	-- -----------------------------------------------------------------
	-- Case: stale registration — the forced clean runs while the
	-- worktree is still registered (teardown moved after it, so the
	-- out-of-band delete leaves a stale registration behind, not a
	-- clean slate): provision prunes the registration and re-creates
	-- the worktree at the same path from the surviving branch.
	-- -----------------------------------------------------------------
	sh(`git -C {quote(MAIN)} clean -ffdx`)
	expect(sh(`test -e {quote(auto.path)}; echo $?`) == "1", "forced clean removed the nested worktree directory")
	expect(
		string.find(sh(`git -C {quote(MAIN)} worktree list --porcelain`), `{auto.path}`, 1, true) ~= nil,
		"the stale registration survived the clean (this is what the self-heal consumes)"
	)
	local healed = worktree.provision({
		repo = MAIN,
		name = "auto-1",
		ref = "origin/main",
		branch = "auto-1",
	})
	expect(healed.path == auto.path, `stale registration heals to the same path: {healed.path}`)
	expect(sh(`test -d {quote(healed.path)}; echo $?`) == "0", "re-created worktree directory exists")
	expect(sh(`git -C {quote(healed.path)} rev-parse HEAD`) == autoHead, "re-created worktree attached to the surviving branch's commit")
	expect(sh(`git -C {quote(healed.path)} rev-parse --abbrev-ref HEAD`) == "auto-1", "re-created worktree is on branch auto-1")
	ptah.log("ok: stale registration (directory deleted out-of-band) pruned; worktree re-created at the same path")
	-- Teardown at the default location, now that the clean cannot race it.
	local autoRemoved = worktree.teardown(healed)
	expect(autoRemoved.ok, `default-parent teardown ok: {tostring(autoRemoved.stderr)}`)

	-- -----------------------------------------------------------------
	-- Case: locked stale registration — git's prune skips locked
	-- worktrees, so the self-heal cannot clear the registration:
	-- provision raises instead of adopting the nonexistent path, and
	-- the registration is left for its owner to unlock.
	-- -----------------------------------------------------------------
	local locked = worktree.provision({
		repo = MAIN,
		name = "locked-1",
		ref = "origin/main",
		branch = "locked-1",
	})
	sh(`git -C {quote(MAIN)} worktree lock {quote(locked.path)}`)
	sh(`rm -rf {quote(locked.path)}`)
	local lockedOk, lockedErr = pcall(function()
		return worktree.provision({
			repo = MAIN,
			name = "locked-1",
			ref = "origin/main",
			branch = "locked-1",
		})
	end)
	expect(lockedOk == false, `locked stale provision raised (got {tostring(lockedErr)})`)
	expect(
		string.find(tostring(lockedErr), "locked", 1, true) ~= nil,
		`locked stale error names the lock: {tostring(lockedErr)}`
	)
	expect(
		string.find(sh(`git -C {quote(MAIN)} worktree list --porcelain`), `{locked.path}`, 1, true) ~= nil,
		"the locked registration survives (provision never unlocks)"
	)
	ptah.log("ok: locked stale registration raises; registration left for its owner")

	-- -----------------------------------------------------------------
	-- Case: live branch occupant — the requested branch is attached to
	-- a different registered worktree whose directory is present:
	-- provision raises naming both paths, before any git command that
	-- would refuse the occupied branch (the ref is the branch's
	-- remote-tracking counterpart, so without the guard the
	-- fast-forward fetch would be the first failure). The occupant
	-- worktree is untouched.
	-- -----------------------------------------------------------------
	local occ = worktree.provision({
		repo = MAIN,
		name = "occ",
		ref = "origin/main",
		branch = "occ-1",
		parent = WTS,
	})
	sh(`git -C {quote(occ.path)} commit --allow-empty -m "occupant work"`)
	local occHead = sh(`git -C {quote(occ.path)} rev-parse HEAD`)
	local occOk, occErr = pcall(function()
		return worktree.provision({
			repo = MAIN,
			name = "occ-victim",
			ref = "origin/occ-1",
			branch = "occ-1",
			parent = WTS,
		})
	end)
	expect(occOk == false, `live-occupant provision raised (got {tostring(occErr)})`)
	expect(
		string.find(tostring(occErr), occ.path, 1, true) ~= nil,
		`live-occupant error names the occupant path: {tostring(occErr)}`
	)
	expect(
		string.find(tostring(occErr), `{WTS}/main-occ-victim`, 1, true) ~= nil,
		`live-occupant error names the target path: {tostring(occErr)}`
	)
	expect(
		string.find(sh(`git -C {quote(MAIN)} worktree list --porcelain`), occ.path, 1, true) ~= nil,
		"the occupant worktree is still registered"
	)
	expect(sh(`git -C {quote(occ.path)} rev-parse HEAD`) == occHead, "the occupant's HEAD is unchanged")
	expect(
		string.find(sh(`git -C {quote(MAIN)} worktree list --porcelain`), `{WTS}/main-occ-victim`, 1, true) == nil,
		"no worktree was registered at the target path by the failed provision"
	)
	ptah.log("ok: live branch occupant raises naming both paths; occupant untouched")

	-- -----------------------------------------------------------------
	-- Case: stale branch occupant — the occupant's directory is
	-- deleted out-of-band while its registration survives (asserted
	-- before the re-provision): the guard prunes the stale
	-- registration and provision succeeds, attaching the fresh target
	-- path to the surviving branch and its commit.
	-- -----------------------------------------------------------------
	local staleOcc = worktree.provision({
		repo = MAIN,
		name = "stale-occ",
		ref = "origin/main",
		branch = "stale-occ-1",
		parent = WTS,
	})
	sh(`git -C {quote(staleOcc.path)} commit --allow-empty -m "stale occupant work"`)
	local staleOccHead = sh(`git -C {quote(MAIN)} rev-parse stale-occ-1`)
	sh(`rm -rf {quote(staleOcc.path)}`)
	expect(
		string.find(sh(`git -C {quote(MAIN)} worktree list --porcelain`), staleOcc.path, 1, true) ~= nil,
		"the stale occupant's registration survived the out-of-band delete"
	)
	local healed = worktree.provision({
		repo = MAIN,
		name = "stale-victim",
		ref = "origin/main",
		branch = "stale-occ-1",
		parent = WTS,
	})
	expect(healed.path == `{WTS}/main-stale-victim`, `stale-occupant heal targets the fresh path: {healed.path}`)
	expect(healed.branch == "stale-occ-1", "healed provision returns the requested branch")
	expect(
		string.find(sh(`git -C {quote(MAIN)} worktree list --porcelain`), staleOcc.path, 1, true) == nil,
		"the stale occupant's registration was retired by the prune"
	)
	expect(sh(`git -C {quote(healed.path)} rev-parse --abbrev-ref HEAD`) == "stale-occ-1", "healed worktree is on the requested branch")
	expect(sh(`git -C {quote(healed.path)} rev-parse HEAD`) == staleOccHead, "healed worktree carries the surviving branch's commit")
	ptah.log("ok: stale branch occupant pruned; worktree provisioned at the target from the surviving branch")

	-- -----------------------------------------------------------------
	-- Case: locked stale branch occupant — the occupant is locked and
	-- its directory deleted: the prune skips it, so provision raises
	-- with the lock-aware wording and the locked registration survives
	-- (still listed, still locked — never unlocked, never removed).
	-- -----------------------------------------------------------------
	local lockedOcc = worktree.provision({
		repo = MAIN,
		name = "locked-occ",
		ref = "origin/main",
		branch = "locked-occ-1",
		parent = WTS,
	})
	sh(`git -C {quote(MAIN)} worktree lock {quote(lockedOcc.path)}`)
	sh(`rm -rf {quote(lockedOcc.path)}`)
	local lockedOccOk, lockedOccErr = pcall(function()
		return worktree.provision({
			repo = MAIN,
			name = "locked-occ-victim",
			ref = "origin/main",
			branch = "locked-occ-1",
			parent = WTS,
		})
	end)
	expect(lockedOccOk == false, `locked-stale-occupant provision raised (got {tostring(lockedOccErr)})`)
	expect(
		string.find(tostring(lockedOccErr), "locked", 1, true) ~= nil,
		`locked-stale-occupant error carries the lock-aware wording: {tostring(lockedOccErr)}`
	)
	expect(
		string.find(tostring(lockedOccErr), lockedOcc.path, 1, true) ~= nil,
		`locked-stale-occupant error names the occupant path: {tostring(lockedOccErr)}`
	)
	expect(
		string.find(sh(`git -C {quote(MAIN)} worktree list --porcelain`), lockedOcc.path, 1, true) ~= nil,
		"the locked registration survives (never removed)"
	)
	expect(
		sh(`git -C {quote(MAIN)} worktree lock {quote(lockedOcc.path)} 2>&1; echo $?`) ~= "0",
		"the registration is still locked (re-locking fails as already locked; never unlocked)"
	)
	ptah.log("ok: locked stale branch occupant raises with the lock-aware wording; registration survives locked")
	return nil
end

local base = sh("mktemp -d")
local ok, err = pcall(runAll, base)
ptah.exec(`rm -rf {quote(base)}`)
if not ok then
	error(tostring(err), 0)
end
ptah.log("worktree-verify: every check passed")
