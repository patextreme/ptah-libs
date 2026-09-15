--!strict
-- Shell helpers (stdlib): a repo-agnostic set of helpers over ptah's
-- exec. ptah.exec never raises for a failed command (any exit code is
-- data), but deterministic setup steps usually have exactly one
-- acceptable outcome, so `mustRun` turns a failure into a script error
-- while `succeeds` keeps any exit code as data. The trim and POSIX
-- quoting helpers are shared so quoting and trim semantics cannot drift
-- between modules (std/gh and std/daemon route through here rather than
-- carrying private copies).

local M = {}

-- Two-sided trim: a command's captured output is often decorated with
-- surrounding whitespace, and a one-sided trim loses the leading half.
function M.trim(s: string): string
	local leading = (s:gsub("^%s+", ""))
	return (leading:gsub("%s+$", ""))
end

-- POSIX sh single-quoting: wrap in single quotes and escape embedded
-- single quotes as '\'' (close, escaped quote, reopen), so a value
-- containing spaces or quotes reaches the command verbatim.
function M.quote(arg: string): string
	return "'" .. (arg:gsub("'", "'\\''")) .. "'"
end

-- Normalize a caught error value (pcall's second return) to a message.
function M.errorMessage(value: any): string
	if type(value) == "string" then
		return value
	end
	return tostring(value)
end

-- Run a command whose only acceptable outcome is exit 0. Returns the
-- trimmed stdout; raises a script error naming the command, its exit
-- code, and its trimmed stderr otherwise.
function M.mustRun(command: string): string
	local result = ptah.exec(command)
	if result.exitCode ~= 0 then
		error(("`%s` failed with exit %d: %s"):format(command, result.exitCode, M.trim(result.stderr)), 0)
	end
	return M.trim(result.stdout)
end

-- Boolean success probe: any exit code is data, never a raise.
function M.succeeds(command: string): boolean
	return ptah.exec(command).exitCode == 0
end

return M
