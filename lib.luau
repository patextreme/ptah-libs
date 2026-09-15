--!strict
-- ptah_libs entry point. Requires the Ptah Playbooks library tree and
-- re-exports it as the named camelCase surface consumers receive through
-- pesde's generated `luau_packages/ptah_libs` shim.
--
-- The entry is deliberately named `lib.luau`, not `init.luau`: a module named
-- `init.luau` has its internal relative requires resolved one directory off
-- under luau-lsp (the analyzer `ptah check` runs).

local agent = require("./std/agent")
local shell = require("./std/shell")
local predicate = require("./std/predicate")
local gh = require("./std/gh")
local daemon = require("./std/daemon")
local sessionConfig = require("./std/session-config")
local escalate = require("./std/escalate")
local openspec = require("./playbooks/openspec/playbook")
local prReviewLoop = require("./playbooks/pr-review-loop/playbook")
local issueWorker = require("./playbooks/issue-worker/playbook")
local ciGate = require("./playbooks/ci-gate/playbook")

return {
	std = {
		agent = agent,
		shell = shell,
		predicate = predicate,
		gh = gh,
		daemon = daemon,
		sessionConfig = sessionConfig,
		escalate = escalate,
	},
	openspec = openspec,
	prReviewLoop = prReviewLoop,
	issueWorker = issueWorker,
	ciGate = ciGate,
}
