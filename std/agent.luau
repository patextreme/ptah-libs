--!strict
-- Agent directory scoping (stdlib): wrap an agent handle so every
-- session it creates runs with a fixed working directory. The Agent
-- type is structural, so the returned handle is accepted anywhere an
-- agent handle is — including the library's own playbooks, which take
-- no `cwd` of their own (by the self-containment rule). The wrapped
-- directory is applied unconditionally, overriding any `cwd` supplied
-- in the session options at the call site, because pinning is the
-- helper's whole purpose.
--
-- This module never constructs an agent: it only wraps a handle the
-- consumer already built with `ptah.agent`. A library module must not
-- call `ptah.agent` literally, so requiring the library never becomes a
-- pre-flight finding for a consumer whose registry lacks a given agent
-- name.

local M = {}

-- Return a handle whose `session` always receives `dir` as its working
-- directory. The caller's options table is not mutated: a fresh table is
-- built per session so a reused options value keeps its own fields.
function M.inDirectory(agent: Agent, dir: string): Agent
	local wrapped: any = {
		session = function(_self: any, opts: SessionOptions?): Session
			local merged: SessionOptions = if opts ~= nil then table.clone(opts) else {}
			merged.cwd = dir
			return agent:session(merged)
		end,
	}
	return wrapped :: Agent
end

return M
