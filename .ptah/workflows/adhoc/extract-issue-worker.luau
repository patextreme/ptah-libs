--!strict
-- Ad-hoc: groom, implement, verify, deliver, and review the
-- extract-issue-worker change.
--
-- Run interactively when human escalation is enabled:
--   ptah run --ask stdin .ptah/workflows/adhoc/extract-issue-worker.luau

-- The repository-local alias points at the package tree, whose entry is lib.luau.
local libs = require("@ptah_libs/lib")

local change = "extract-issue-worker"
local agent = ptah.agent("pi")

local sessionConfig = { { id = "model", value = "ollama-cloud/deepseek-v4.1-flash" } }
local judgeSessionConfig = { { id = "model", value = "ollama-cloud/deepseek-v4.1-flash" } }
local reporterSessionConfig = { { id = "model", value = "ollama-cloud/deepseek-v4.1-flash" } }

local ops = libs.openspec.new({
	agent = agent,
	judgeAgent = agent,
	sessionConfig = sessionConfig,
	judgeSessionConfig = judgeSessionConfig,
})

-- Groom, implement, and verify the change; verify also syncs and archives it.
ops:groom(change)
ops:implement(change)
ops:verify(change)

-- Commit the implemented change, push the branch, and open or reuse its PR.
local staged = ptah.exec("git add -A")
if staged.exitCode ~= 0 then
	error(`extract-issue-worker: git add failed: {staged.stderr}`, 0)
end

local stagedDiff = ptah.exec("git diff --cached --quiet")
if stagedDiff.exitCode == 1 then
	local commit = ptah.exec(`git commit -m "feat: implement {change}"`)
	if commit.exitCode ~= 0 then
		error(`extract-issue-worker: commit failed: {commit.stderr}`, 0)
	end
elseif stagedDiff.exitCode ~= 0 then
	error(`extract-issue-worker: could not inspect staged changes: {stagedDiff.stderr}`, 0)
end

local push = ptah.exec("git push -u origin HEAD")
if push.exitCode ~= 0 then
	error(`extract-issue-worker: push failed: {push.stderr}`, 0)
end

local gh = libs.std.gh
local prUrl: string? = nil
local existing = gh.run({ "pr", "view", "--json", "url" }, { json = true })
if existing.ok and existing.json ~= nil then
	local data = existing.json :: { url: string }
	prUrl = data.url
	ptah.log(`extract-issue-worker: reusing {prUrl}`)
else
	local created = gh.run({ "pr", "create", "--fill" })
	if not created.ok then
		error(`extract-issue-worker: could not open PR: {created.stderr}`, 0)
	end
	local viewed = gh.run({ "pr", "view", "--json", "url" }, { json = true })
	if not viewed.ok or viewed.json == nil then
		error(`extract-issue-worker: could not read created PR URL: {viewed.stderr}`, 0)
	end
	local data = viewed.json :: { url: string }
	prUrl = data.url
	ptah.log(`extract-issue-worker: opened {prUrl}`)
end

if prUrl == nil or prUrl == "" then
	error("extract-issue-worker: PR URL was empty", 0)
end

local loop = libs.prReviewLoop.new({
	agent = agent,
	judgeAgent = agent,
	reporterAgent = agent,
	sessionConfig = sessionConfig,
	judgeSessionConfig = judgeSessionConfig,
	reporterSessionConfig = reporterSessionConfig,
	maxIterations = 5,
	dryRun = false,
})

local outcome = loop:review(prUrl)
ptah.log(`extract-issue-worker: review {outcome.status} — {prUrl}`)
ptah.log(outcome.report)

if outcome.status ~= "converged" then
	ptah.exit(1)
end
