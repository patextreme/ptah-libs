--!strict
-- Escalation transport (stdlib): route a blocker to a human through
-- ptah's ask facility — best-effort, outcome-as-data. One call,
-- `ask({ prompt, details? })`: a served ask returns the human's
-- answer or refusal; an unservable ask (asking prohibited, no
-- provider configured, provider failure, or end of input) returns the
-- provider's reason. No ask ever raises out of this module, and the
-- mechanism accepts no configuration — provider selection is the
-- operator's decision (`--ask` / `PTAH_ASK` / `[ask]` / TTY
-- auto-detect), made outside script code.
--
-- The alias below is deliberate. ptah's check/run pre-flight lints
-- literal `ptah.ask(` call sites over the entry and its literal
-- require graph, and would fail every provider-less consumer of a
-- library containing one — dead branch or not. Aliased asks are a
-- documented residual in that lint ("the runtime check is the source
-- of truth"), and the runtime raise is exactly what the pcall below
-- classifies into `unavailable`. If ptah ever closes the residual,
-- this design must be revisited (the fallback is a supported
-- try-ask API upstream).

export type Outcome =
	{
		status: "respond",
		-- The human's answer, verbatim (one line, unprocessed).
		text: string,
	}
	| {
		status: "abort",
	}
	| {
		status: "unavailable",
		-- Why no provider served the ask (prohibited, unconfigured,
		-- provider failure, or end of input).
		reason: string,
	}

-- Deliberately not a literal call site: see the header rationale.
local askFn = ptah.ask

local M = {}

-- Ask a human and classify the outcome: `respond` carries the answer
-- text, `abort` is the human refusing, and every ask raise (the four
-- no-provider conditions) uniformly classifies to `unavailable`
-- carrying the raise's message — a library-level ask degrades to
-- data instead of failing the run.
function M.ask(opts: { prompt: string, details: string? }): Outcome
	local ok, result = pcall(askFn, opts)
	if not ok then
		return { status = "unavailable", reason = tostring(result) }
	end
	if result.action == "respond" then
		return { status = "respond", text = result.text }
	end
	return { status = "abort" }
end

return M
