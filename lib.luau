--!strict
-- ptah_libs entry point. Requires the Ptah Playbooks library tree and
-- re-exports it as the named camelCase surface consumers receive through
-- pesde's generated `luau_packages/ptah_libs` shim.
--
-- The entry is deliberately named `lib.luau`, not `init.luau`: a module named
-- `init.luau` has its internal relative requires resolved one directory off
-- under luau-lsp (the analyzer `ptah check` runs).

local predicate = require("./std/predicate")
local gh = require("./std/gh")
local daemon = require("./std/daemon")
local sessionConfig = require("./std/session-config")
local escalate = require("./std/escalate")
local worktree = require("./std/worktree")
local openspec = require("./playbooks/openspec/playbook")
local pr = require("./playbooks/pr/playbook")
local issue = require("./playbooks/issue/playbook")
local factory = require("./playbooks/factory/playbook")

return {
	std = {
		predicate = predicate,
		gh = gh,
		daemon = daemon,
		sessionConfig = sessionConfig,
		escalate = escalate,
		worktree = worktree,
	},
	openspec = openspec,
	pr = pr,
	issue = issue,
	factory = factory,
}
