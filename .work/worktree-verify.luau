--!strict
-- Verification harness for the worktree-default-under-ptah change
-- (uncommitted `.work/` scratch): ports the worktree-aware-playbooks
-- change's inline resolution/teardown cases — fresh provision,
-- adopt-as-is, fast-forward, diverge-errors; teardown clean, dirty
-- refusal, branch survival — all passing `parent` explicitly (expected
-- unaffected), and adds the default-parent case: provision without
-- `parent` against the throwaway repo lands at
-- `<MAIN>/.ptah/worktree/main-<name>` with the parent auto-created, and
-- adoption and teardown behave as before.
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
	local autoRemoved = worktree.teardown(autoAdopted)
	expect(autoRemoved.ok, `default-parent teardown ok: {tostring(autoRemoved.stderr)}`)
	ptah.log("ok: default parent is <MAIN>/.ptah/worktree, auto-created; adoption and teardown behave as before")
	return nil
end

local base = sh("mktemp -d")
local ok, err = pcall(runAll, base)
ptah.exec(`rm -rf {quote(base)}`)
if not ok then
	error(tostring(err), 0)
end
ptah.log("worktree-verify: every check passed")
