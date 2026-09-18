--!strict
-- openspec component: groom, implement, and verify a named openspec
-- change. Convergence is this component's own loop over std.predicate
-- — prompt, judge, escalate to a human or fix, repeat, bounded by the
-- iteration cap — following the shared loop conventions documented in
-- ../README.md. See README.md in this directory for the declared
-- environment requirements.

local predicate = require("../../std/predicate")
local sessionConfig = require("../../std/session-config")
local escalate = require("../../std/escalate")

export type Config = {
	-- Work agent handle driving the openspec skills.
	agent: Agent,
	-- Judge agent handle for the typed predicates (can be the same
	-- handle with a different model).
	judgeAgent: Agent,
	-- Ordered session-config entries applied to every work session the
	-- component creates: every per-iteration session of groom,
	-- implement, and verify, and verify's archive session.
	sessionConfig: { sessionConfig.Entry }?,
	-- Ordered session-config entries applied to every judge and
	-- human-escalation-probe session (forwarded into every predicate
	-- call).
	judgeSessionConfig: { sessionConfig.Entry }?,
	-- Absolute working directory for every session this component
	-- creates (work, judge, human-escalation-probe, and archive
	-- sessions alike). Nil keeps today's behavior: sessions run in the
	-- invocation directory. The playbook stays git-agnostic — this is
	-- just a directory; provisioning it is the calling shim's business.
	workingDir: string?,
	-- The removed model fields, kept nil-typed so a configured value
	-- is a type error naming the field (the analyzer does not flag
	-- unknown keys): a model choice is an ordinary sessionConfig entry.
	model: nil,
	judgeModel: nil,
	-- Convergence cap shared by every operation (default 10).
	maxIterations: number?,
}

export type Instance = {
	-- Converge the change's proposal through review.
	groom: (self: Instance, change: string) -> string,
	-- Drive task execution to completion. The optional task scope
	-- narrows the run (and the judge's acceptance) to the tasks
	-- matching the free-text scope; nil scopes to every task of the
	-- change.
	implement: (self: Instance, change: string, scope: string?) -> string,
	-- Converge verification, then sync and archive the change in the
	-- same operation.
	verify: (self: Instance, change: string) -> string,
}

local DEFAULT_MAX_ITERATIONS = 10

-- The component-owned autonomy clause, appended to every work prompt here
-- in drive()'s prompt composition — one site covering all three operations.
-- Component-owned like the protocol layer, so it cannot be configured away:
-- judgment calls are the agent's to take (only an operator-owned decision
-- escalates), the pass output must surface each call it made, and
-- confirmation-seeking never pays because the loop re-judges every pass.
local AUTONOMY_CLAUSE = "Make judgment calls autonomously, note each in your output as 'judgment call: …', the loop re-judges every pass, and never wait for confirmation."

local M = {}

function M.new(config: Config): Instance
	local maxIterations = if config.maxIterations ~= nil then config.maxIterations else DEFAULT_MAX_ITERATIONS
	local work: Agent = config.agent

	-- Prompt, judge the output, escalate or fix, repeat — bounded.
	-- The probe/human/resolve texts are per-operation data: each
	-- operation speaks its own terminal vocabulary (findings for
	-- groom/verify, the apply skill's pause states for implement) over
	-- the same skeleton. Escalation composes the ask's identity line
	-- from the same data (`{sessionId} {change}`) and routes through
	-- std/escalate: a served ask resumes the loop, abort/unavailable
	-- fail the operation.
	local function drive(
		sessionId: string,
		prompt: string,
		opts: {
			change: string,
			accepted: string,
			probePrompt: string,
			humanPredicate: string,
			resolvePrompt: string,
		}
	): string
		for iteration = 0, maxIterations - 1 do
			local header = `[{sessionId} iteration {iteration + 1} of {maxIterations}]\n`
			local session: Session = work:session({ id = `{sessionId}:{iteration}`, cwd = config.workingDir })
			sessionConfig.apply(session, config.sessionConfig)

			local outcome = session:prompt(header .. prompt .. "\n\n" .. AUTONOMY_CLAUSE)
			if
				predicate(opts.accepted, outcome.text, {
					agent = config.judgeAgent,
					sessionId = `{sessionId}-judge:{iteration}`,
					sessionConfig = config.judgeSessionConfig,
					cwd = config.workingDir,
				})
			then
				session:close()
				return outcome.text
			end

			-- A judge-rejected pass probes for human input before any
			-- fix. A confirmed need escalates through std/escalate: the
			-- ask pauses only this loop — the work session stays open —
			-- and the outcome decides between resume and fail.
			local probe = session:prompt(header .. opts.probePrompt)
			local needsHuman = predicate(opts.humanPredicate, probe.text, {
				agent = config.judgeAgent,
				sessionId = `{sessionId}-escalate-judge:{iteration}`,
				sessionConfig = config.judgeSessionConfig,
				cwd = config.workingDir,
			})
			if needsHuman then
				local answer = escalate.ask({
					prompt = `{sessionId} {opts.change}: human input required (iteration {iteration + 1} of {maxIterations})`,
					details = `work session: {session:label()}\nagent session: {session:sessionId()}\n\n{probe.text}`,
				})
				if answer.status == "respond" then
					-- The answer is the session's next prompt, verbatim —
					-- no header, no framing: the human is driving the agent.
					-- The iteration then ends like any other, counted
					-- against the cap, and the loop re-judges the result of
					-- the human-guided pass.
					session:prompt(answer.text)
					session:close()
					continue
				elseif answer.status == "abort" then
					session:close()
					error(`{sessionId}: human aborted escalation (iteration {iteration + 1} of {maxIterations})`)
				else
					-- No ask provider served the request: today's
					-- failure, byte-identical.
					session:close()
					local excerpt = string.gsub(string.sub(probe.text, 1, 200), "[\r\n]", " ")
					error(
						`{sessionId}: human input is required (iteration {iteration + 1} of {maxIterations}): {excerpt}`
					)
				end
			end

			session:prompt(header .. opts.resolvePrompt)
			session:close()
		end
		return error(`{sessionId}: did not converge within {maxIterations} iterations`)
	end

	local instance: Instance = {
		groom = function(_self: Instance, change: string): string
			ptah.log(`openspec: reviewing change {change}`)
			local text =
				drive("opsx-groom", `Review the openspec change named {change} using the openspec-review skill`, {
					change = change,
					accepted = "The review does not contain any blocker findings",
					probePrompt = "For the blocking findings, resolve them yourself and let the loop re-judge the result — make any judgment call autonomously and proceed with the option you judge best. Ask for human input only when a finding requires an operator-owned decision you have no authority to take (for example product direction, architecture, or scope) whose wrong outcome the loop cannot reverse at bounded cost; if so, state that decision. A confirmation, an approval to proceed, or a mechanical choice does not count — pick one and proceed.",
					humanPredicate = "Resolving the blocking findings requires an operator-owned decision — one the agent has no authority to take and the loop cannot reverse at bounded cost; a confirmation or a mechanical choice does not count",
					resolvePrompt = "Go ahead and resolve the blocking findings",
				})
			ptah.log(`openspec: change {change} is ready to implement`)
			return text
		end,
		implement = function(_self: Instance, change: string, scope: string?): string
			-- A task scope interpolates into exactly two places: the work
			-- prompt (which redefines the job as the scoped tasks) and the
			-- accepted predicate (the judge never sees the work prompt, so
			-- the scope must ride inside the predicate). A scope that
			-- matches no tasks dead-ends through the prompt's "state it,
			-- don't guess" clause into the pause -> human-escalation path
			-- below. Nil scope keeps today's strings byte-for-byte.
			local prompt: string
			local accepted: string
			if scope ~= nil then
				ptah.log(`openspec: implementing change {change} (task scope: {scope})`)
				prompt =
					`Implement the pending tasks of the openspec change named {change} using the openspec-apply-change skill. The task scope for this run is: {scope}. Treat the tasks matching the scope as the entire job: implement those, leave all other tasks pending, and end each pass either with the scoped tasks implemented or paused with a stated reason, as the skill defines those states. If the task scope matches no tasks, end the pass stating that; do not guess or substitute.`
				accepted = `All tasks in the following task scope are implemented: "{scope}"`
			else
				ptah.log(`openspec: implementing change {change}`)
				prompt =
					`Implement the pending tasks of the openspec change named {change} using the openspec-apply-change skill. End each pass either with all tasks implemented or paused with a stated reason, as the skill defines those states.`
				accepted = "All tasks of the change are implemented"
			end
			local text = drive("opsx-implement", prompt, {
				change = change,
				accepted = accepted,
				probePrompt = "For the pause, resolve it yourself and continue implementing — make any judgment call autonomously (for example updating the change's artifacts per the apply skill) and proceed with the option you judge best. Ask for human input only when continuing requires an operator-owned decision you have no authority to take (for example product direction, architecture, or scope) whose wrong outcome the loop cannot reverse at bounded cost; if so, state that decision. A confirmation, an approval to proceed, or a mechanical choice does not count — pick one and proceed.",
				humanPredicate = "Continuing requires an operator-owned decision — one the agent has no authority to take and the loop cannot reverse at bounded cost; a confirmation or a mechanical choice does not count",
				resolvePrompt = "Go ahead and resolve the pause yourself, then continue implementing the remaining tasks",
			})
			ptah.log(`openspec: change {change} is implemented`)
			return text
		end,
		verify = function(_self: Instance, change: string): string
			ptah.log(`openspec: verifying change {change}`)
			local text = drive(
				"opsx-verify",
				`Verify the implementation of the openspec change named {change} using the openspec-verify-change skill`,
				{
					change = change,
					accepted = "The verification does not contain critical findings or warnings",
					probePrompt = "For the critical findings and warnings, resolve them yourself and let the loop re-judge the result — make any judgment call autonomously and proceed with the option you judge best. Ask for human input only when a finding requires an operator-owned decision you have no authority to take (for example product direction, architecture, or scope) whose wrong outcome the loop cannot reverse at bounded cost; if so, state that decision. A confirmation, an approval to proceed, or a mechanical choice does not count — pick one and proceed.",
					humanPredicate = "Resolving the critical findings and warnings requires an operator-owned decision — one the agent has no authority to take and the loop cannot reverse at bounded cost; a confirmation or a mechanical choice does not count",
					resolvePrompt = "Go ahead and resolve the critical findings and warnings",
				}
			)
			-- The sync-and-archive step is part of the same operation: it
			-- runs once the verification loop has converged.
			local archiver: Session = work:session({ id = "opsx-archiver", cwd = config.workingDir })
			sessionConfig.apply(archiver, config.sessionConfig)
			archiver:prompt(`Please sync and archive the change {change}`)
			archiver:close()
			ptah.log(`openspec: change {change} synced and archived`)
			return text
		end,
	}
	return instance
end

return M
