--!strict
-- ptah_libs entry point. Requires the Factory Components library tree and
-- re-exports it as the named camelCase surface consumers receive through
-- pesde's generated `luau_packages/ptah_libs` shim.
--
-- The entry is deliberately named `lib.luau`, not `init.luau`: a module named
-- `init.luau` has its internal relative requires resolved one directory off
-- under luau-lsp (the analyzer `ptah check` runs).

local predicate = require("./factory-components/std/predicate")
local gh = require("./factory-components/std/gh")
local daemon = require("./factory-components/std/daemon")
local sessionConfig = require("./factory-components/std/session-config")
local openspec = require("./factory-components/components/openspec/component")
local prReviewLoop = require("./factory-components/components/pr-review-loop/component")

return {
	std = {
		predicate = predicate,
		gh = gh,
		daemon = daemon,
		sessionConfig = sessionConfig,
	},
	openspec = openspec,
	prReviewLoop = prReviewLoop,
}