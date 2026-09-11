--!strict
-- PR review loop playbook: run a convergent review→validate→fix→verify loop
-- against a pull request. Repo specifics (reviewer persona, blocking
-- taxonomy, dry-run gating) arrive as config; the PR URL is the sole
-- repository context. The work session reviews freely in prose following its
-- persona; a typed judge session (a `resultSchema` result) is the schema
-- boundary that converts that prose into structured findings, reconciles
-- them with the ledger, and computes convergence (`openBlocking == 0`). The
-- loop's cross-round memory is a ledger stored in a dedicated PR comment,
-- updated in place, and resumed automatically. See README.md for the
-- three-layer instruction contract and the declared environment
-- requirements.
--
-- Loop shape (this playbook's own policy over std/predicate's typed-result
-- pattern and std/escalate):
--   * discovery pass (full-PR review) when no ledger exists, then delta
--     reviews against the ledger's `lastReviewedSha`;
--   * a typed judge converts the prose into findings, reconciles the open
--     ledger findings, and flags `needsHuman`;
--   * convergence is `no open blocking findings` — deferred findings never
--     gate;
--   * a fix turn batches all open blocking findings by root cause, then
--     commit-and-push (gated by dry-run);
--   * a fix is issued only when budget remains, so every push is followed
--     by at least one review pass;
--   * the judge's `needsHuman` flag routes through std/escalate — a served
--     answer resumes the still-open work session, abort/unavailable fail.

local gh = require("../../std/gh")
local sessionConfig = require("../../std/session-config")
local escalate = require("../../std/escalate")
local defaultInstruction = require("./default-instruction")
local protocol = require("./protocol")

export type Severity = "blocking" | "non-blocking"
export type ValidationStatus = "validated" | "refuted" | "unvalidated"
export type FindingStatus = "open" | "fixed" | "deferred" | "accepted"

-- One ledger finding: the durable record of an issue across passes.
export type LedgerFinding = {
	id: string,
	-- A short description of the issue, carried so a later (fresh) fix
	-- session can act on the finding without the original review context.
	title: string,
	family: string,
	severity: Severity,
	validation: ValidationStatus,
	status: FindingStatus,
	-- The commit that carried the fix, once a fix turn has pushed one.
	fixCommit: string?,
}

-- The playbook-owned ledger: PR identity, the discovery and last-reviewed
-- SHAs, the PR's intention, the findings, the family table, and the count of
-- findings compacted away once verified clean.
export type Ledger = {
	pr: string,
	discoverySha: string,
	lastReviewedSha: string,
	intention: string,
	findings: { LedgerFinding },
	families: { string },
	resolvedCount: number,
}

-- One judge finding: the judge's typed read of the review prose.
export type JudgeFinding = {
	severity: Severity,
	family: string,
	validation: ValidationStatus,
	-- The judge's determination that resolving this finding needs a human.
	needsHuman: boolean,
	-- `deferred` marks an important finding outside the PR's intention: it
	-- never gates convergence.
	status: "open" | "deferred" | "accepted",
	-- A short description of the issue (one line).
	title: string,
}

-- The judge's reconciliation of one ledger finding it was shown.
export type JudgeReconciliation = {
	id: string,
	status: "resolved" | "open",
	evidence: string?,
	-- Set when resolving a still-open finding needs a human decision.
	needsHuman: boolean?,
}

-- The judge session's typed result.
export type Findings = {
	findings: { JudgeFinding },
	priorFindingsStatus: { JudgeReconciliation },
}

-- The `review` operation's outcome: outcomes as data, so the caller's script
-- can gate its own post-loop steps (CI, gates) on the loop's end state.
export type Outcome = {
	status: "converged" | "non-converged",
	verdict: string,
	ledger: Ledger,
}

export type Config = {
	-- Work agent handle reviewing and fixing the PR (and posting the verdict
	-- comment on convergence).
	agent: Agent,
	-- Judge agent handle for the typed findings session. Required: the loop's
	-- convergence is computed from the judge's typed output, and there is no
	-- prose-parsing fallback.
	judgeAgent: Agent,
	-- Ordered session-config entries applied to every work session the
	-- playbook creates: each review/fix iteration's session, which also posts
	-- the verdict comment.
	sessionConfig: { sessionConfig.Entry }?,
	-- Ordered session-config entries applied to every judge session.
	judgeSessionConfig: { sessionConfig.Entry }?,
	-- The removed model fields, kept nil-typed so a configured value is a
	-- type error naming the field (the analyzer does not flag unknown keys):
	-- a model choice is an ordinary sessionConfig entry.
	model: nil,
	judgeModel: nil,
	-- The persona layer: the reviewer instruction as direct text. A configured
	-- value fully replaces the built-in default persona (only nil selects the
	-- default; an empty string stays configured). It carries no classification
	-- duties — the reviewer reviews freely in prose, and the component-owned
	-- protocol fragment is appended to every review prompt regardless.
	reviewInstruction: string?,
	-- The taxonomy layer: free text supplied to the judge defining what counts
	-- as blocking for this repository. It reaches the judge, never the persona.
	blockingAdditions: string?,
	-- When true the commit/push step is skipped: the loop converges on
	-- reviews and fixes but never pushes to the PR branch.
	dryRun: boolean?,
	-- Convergence cap (default 8) over loop units; a fix turn is issued only
	-- when budget remains.
	maxIterations: number?,
}

export type Instance = {
	-- Run the review loop against one pull request (the PR URL is per-call
	-- data, not config). Returns the typed outcome.
	review: (self: Instance, prUrl: string) -> Outcome,
}

local DEFAULT_MAX_ITERATIONS = 8
local DEFAULT_JUDGE_ATTEMPTS = 3
local LEDGER_MARKER = "<!-- ptah:pr-review-ledger -->"

-- The judge session's result contract: typed findings plus the reconciliation
-- of the ledger findings the judge was shown.
local FINDINGS_SCHEMA: { [string]: any } = {
	type = "object",
	additionalProperties = false,
	properties = {
		findings = {
			type = "array",
			items = {
				type = "object",
				additionalProperties = false,
				properties = {
					severity = { type = "string", enum = { "blocking", "non-blocking" } },
					family = { type = "string" },
					validation = { type = "string", enum = { "validated", "refuted", "unvalidated" } },
					needsHuman = { type = "boolean" },
					status = { type = "string", enum = { "open", "deferred", "accepted" } },
					title = { type = "string" },
				},
				required = { "severity", "family", "validation", "needsHuman", "status", "title" },
			},
		},
		priorFindingsStatus = {
			type = "array",
			items = {
				type = "object",
				additionalProperties = false,
				properties = {
					id = { type = "string" },
					status = { type = "string", enum = { "resolved", "open" } },
					evidence = { type = "string" },
					needsHuman = { type = "boolean" },
				},
				required = { "id", "status" },
			},
		},
	},
	required = { "findings", "priorFindingsStatus" },
}

-- ---------------------------------------------------------------------------
-- Ledger transport (std/gh)
-- ---------------------------------------------------------------------------

local function parsePrUrl(prUrl: string): { owner: string, repo: string, number: string }?
	local owner, repo, number = string.match(prUrl, "^https?://github%.com/([^/]+)/([^/]+)/pull/(%d+)")
	if owner == nil or repo == nil or number == nil then
		return nil
	end
	return { owner = owner, repo = repo, number = number }
end

local function ledgerBody(ledger: Ledger): string
	return LEDGER_MARKER .. "\n\n```json\n" .. ptah.json.stringify(ledger, { indent = 2 }) .. "\n```\n"
end

local function parseLedgerBody(body: string): Ledger?
	local block = string.match(body, "```json%s*\n(.-)\n```")
	if block == nil then
		return nil
	end
	local ok, value = pcall(ptah.json.parse, block)
	if not ok then
		return nil
	end
	return value :: Ledger
end

-- The comment's numeric REST id. `gh pr view --json comments` carries the
-- node id (a string) alongside the URL; the REST PATCH needs the database id,
-- which the URL's `#issuecomment-<n>` fragment always carries.
local function commentDatabaseId(comment: any): number?
	local url = comment.url
	if type(url) == "string" then
		local id = string.match(url, "#issuecomment%-(%d+)")
		if id ~= nil then
			return tonumber(id)
		end
	end
	local id = comment.id
	if type(id) == "number" then
		return id
	end
	return nil
end

-- Flatten `gh api --paginate --slurp` output defensively: a page is an array
-- of comments, a flat response is an array of comments. Both are accepted.
local function collectComments(raw: any): { any }
	local out: { any } = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, entry in raw do
		if type(entry) == "table" and entry.body == nil then
			for _, comment in entry do
				table.insert(out, comment)
			end
		else
			table.insert(out, entry)
		end
	end
	return out
end

local function readLedger(prUrl: string): { ledger: Ledger?, commentId: number? }
	local ref = parsePrUrl(prUrl)
	if ref == nil then
		error(`pr-review: {prUrl} is not a GitHub pull request URL`)
	end
	local path = `/repos/{ref.owner}/{ref.repo}/issues/{ref.number}/comments`
	local outcome = gh.run({ "api", "--paginate", "--slurp", path }, { json = true })
	if not outcome.ok then
		error(`pr-review: could not read PR comments for {prUrl}: {outcome.stderr}`)
	end
	for _, comment in collectComments(outcome.json) do
		local body = comment.body
		if type(body) == "string" and string.find(body, LEDGER_MARKER, 1, true) ~= nil then
			return { ledger = parseLedgerBody(body), commentId = commentDatabaseId(comment) }
		end
	end
	return { ledger = nil, commentId = nil }
end

local function createLedgerComment(prUrl: string, ledger: Ledger): number?
	local ref = parsePrUrl(prUrl)
	if ref == nil then
		error(`pr-review: {prUrl} is not a GitHub pull request URL`)
	end
	local path = `/repos/{ref.owner}/{ref.repo}/issues/{ref.number}/comments`
	local outcome = gh.run({ "api", "--method", "POST", path, "-f", `body={ledgerBody(ledger)}` }, { json = true })
	if not outcome.ok then
		error(`pr-review: could not create the ledger comment on {prUrl}: {outcome.stderr}`)
	end
	local id = outcome.json.id
	if type(id) == "number" then
		return id
	end
	return nil
end

local function updateLedgerComment(prUrl: string, commentId: number, ledger: Ledger)
	local ref = parsePrUrl(prUrl)
	if ref == nil then
		error(`pr-review: {prUrl} is not a GitHub pull request URL`)
	end
	local path = `/repos/{ref.owner}/{ref.repo}/issues/comments/{commentId}`
	local outcome = gh.run({ "api", "--method", "PATCH", path, "-f", `body={ledgerBody(ledger)}` }, { json = true })
	if not outcome.ok then
		error(`pr-review: could not update the ledger comment on {prUrl}: {outcome.stderr}`)
	end
end

local function fetchHeadSha(prUrl: string): string
	local outcome = gh.run({ "pr", "view", prUrl, "--json", "headRefOid" }, { json = true })
	if not outcome.ok then
		error(`pr-review: could not read the PR head for {prUrl}: {outcome.stderr}`)
	end
	local sha = outcome.json.headRefOid
	if type(sha) ~= "string" then
		error(`pr-review: the PR head for {prUrl} carried no commit SHA`)
	end
	return sha
end

local function lastCommitMessage(commits: any): string
	if type(commits) ~= "table" then
		return ""
	end
	local last = commits[#commits]
	if type(last) ~= "table" then
		return ""
	end
	local body = last.messageBody
	if type(body) == "string" and body ~= "" then
		return body
	end
	local headline = last.messageHeadline
	if type(headline) == "string" and headline ~= "" then
		return headline
	end
	local message = last.message
	if type(message) == "string" then
		return message
	end
	return ""
end

-- Intention capture at discovery: the PR title/body when the body is present;
-- otherwise the last commit message before the first ledger record.
local function fetchDiscovery(prUrl: string): { sha: string, intention: string }
	local outcome = gh.run({ "pr", "view", prUrl, "--json", "title,body,headRefOid,commits" }, { json = true })
	if not outcome.ok then
		error(`pr-review: could not read the PR for {prUrl}: {outcome.stderr}`)
	end
	local data = outcome.json
	local sha = data.headRefOid
	if type(sha) ~= "string" then
		error(`pr-review: the PR head for {prUrl} carried no commit SHA`)
	end
	local title = if type(data.title) == "string" then data.title else ""
	local body = if type(data.body) == "string" then data.body else ""
	local intention: string
	if body ~= "" then
		intention = if title ~= "" then title .. "\n\n" .. body else body
	else
		local fallback = lastCommitMessage(data.commits)
		intention = if title ~= "" then title .. "\n\n" .. fallback else fallback
	end
	return { sha = sha, intention = intention }
end

-- ---------------------------------------------------------------------------
-- Ledger state helpers
-- ---------------------------------------------------------------------------

local function contains(list: { string }, value: string): boolean
	for _, item in list do
		if item == value then
			return true
		end
	end
	return false
end

local function hasOpenBlocking(ledger: Ledger): boolean
	for _, finding in ledger.findings do
		if finding.severity == "blocking" and finding.status == "open" then
			return true
		end
	end
	return false
end

local function nextFindingId(ledger: Ledger): number
	local maxN = ledger.resolvedCount
	for _, finding in ledger.findings do
		local n = tonumber(string.match(finding.id, "^f(%d+)$") or "")
		if n ~= nil and n > maxN then
			maxN = n
		end
	end
	return maxN + 1
end

local function ledgerSummary(ledger: Ledger?): string
	if ledger == nil then
		return "Ledger state: none yet (this is the discovery pass)."
	end
	local lines = { "Ledger state:", `- last reviewed commit: {ledger.lastReviewedSha}` }
	if #ledger.families > 0 then
		table.insert(lines, `- known finding families: {table.concat(ledger.families, ", ")}`)
	end
	local openFindings: { string } = {}
	for _, finding in ledger.findings do
		if finding.status == "open" then
			table.insert(
				openFindings,
				`{finding.id} ({finding.severity}, family {finding.family}, validation {finding.validation}): {finding.title}`
			)
		end
	end
	if #openFindings > 0 then
		table.insert(lines, `- open findings: {table.concat(openFindings, "; ")}`)
	else
		table.insert(lines, "- open findings: none")
	end
	return table.concat(lines, "\n")
end

local function findingList(ledger: Ledger, status: FindingStatus, severity: Severity?): { string }
	local lines: { string } = {}
	for _, finding in ledger.findings do
		if finding.status == status and (severity == nil or finding.severity == severity) then
			table.insert(
				lines,
				`- {finding.id} ({finding.severity}, family {finding.family}, validation {finding.validation}): {finding.title}`
			)
		end
	end
	return lines
end

-- Reconcile the judge's typed output into the ledger: compact findings the
-- judge verified clean in a later pass into the resolved count, keep the rest,
-- and append the judge's new findings with fresh ids.
local function applyFindings(ledger: Ledger, findings: Findings)
	local resolved: { [string]: boolean } = {}
	for _, rec in findings.priorFindingsStatus do
		if rec.status == "resolved" then
			resolved[rec.id] = true
		end
	end
	local kept: { LedgerFinding } = {}
	local compacted = 0
	for _, finding in ledger.findings do
		if finding.status == "open" and resolved[finding.id] then
			compacted += 1
		else
			table.insert(kept, finding)
		end
	end
	ledger.findings = kept
	ledger.resolvedCount += compacted

	local nextId = nextFindingId(ledger)
	for _, judgeFinding in findings.findings do
		table.insert(ledger.findings, {
			id = `f{nextId}`,
			title = judgeFinding.title,
			family = judgeFinding.family,
			severity = judgeFinding.severity,
			validation = judgeFinding.validation,
			status = judgeFinding.status,
			fixCommit = nil,
		})
		nextId += 1
		if not contains(ledger.families, judgeFinding.family) then
			table.insert(ledger.families, judgeFinding.family)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Prompt assembly
-- ---------------------------------------------------------------------------

-- Persona + protocol fragment + phase directive + ledger data. The protocol
-- is appended for both a configured persona and the built-in default.
local function buildReviewPrompt(persona: string, prUrl: string, ledger: Ledger?, discovery: boolean): string
	local phase: string
	if discovery or ledger == nil then
		phase = `Review the entire pull request {prUrl}. This is the discovery pass: do not limit yourself to recent changes.`
	else
		phase =
			`Review only the changes made since the last reviewed commit ({ledger.lastReviewedSha}) on pull request {prUrl}.`
	end
	return table.concat({ persona, protocol, phase, ledgerSummary(ledger) }, "\n\n---\n\n")
end

local function buildJudgePrompt(
	prUrl: string,
	reviewText: string,
	ledger: Ledger,
	intention: string,
	blockingAdditions: string?
): string
	local taxonomy = if blockingAdditions ~= nil and blockingAdditions ~= "" then blockingAdditions
		else "(none configured — use your judgement for what counts as blocking)"
	return table.concat({
		`Convert the pull request review prose below into typed findings for {prUrl}.`,
		"",
		"## PR intention",
		intention,
		"",
		"## Blocking taxonomy for this repository",
		taxonomy,
		"",
		"## Ledger (previous state)",
		ledgerSummary(ledger),
		"",
		"## Rules",
		"- Classify each finding as blocking or non-blocking, give it a family name, and give it a one-line title describing the issue.",
		"- Record the validation status the reviewer reported (validated, refuted, or unvalidated).",
		"- A finding that is important but outside the PR's intention is deferred: give it status \"deferred\". A deferred finding never blocks convergence.",
		"- Report a recurrence of a ledger finding against that finding's id, not as a new finding.",
		"- For every open ledger finding, report in priorFindingsStatus whether it is resolved (with evidence) or still open, and set needsHuman if resolving it requires a human decision.",
		"- Set needsHuman true on a finding only when resolving it requires a human decision.",
		"",
		"## Review prose",
		reviewText,
	}, "\n")
end

-- Both prompts name the PR explicitly. A fresh resume session (a fix turn
-- or the immediate-converge session) never saw a review prompt, so the PR
-- URL is the only repository context it has.
local function buildFixPrompt(prUrl: string, ledger: Ledger, header: string): string
	local lines = {
		header
			.. `Resolve all of the following blocking findings on pull request {prUrl} in a single pass, addressing each finding's root cause rather than each symptom separately:`,
	}
	for _, line in findingList(ledger, "open", "blocking") do
		table.insert(lines, line)
	end
	return table.concat(lines, "\n")
end

local function buildVerdictPrompt(prUrl: string, ledger: Ledger, header: string): string
	local deferred = findingList(ledger, "deferred")
	local deferredText = if #deferred > 0 then table.concat(deferred, "\n") else "(none)"
	return table.concat({
		header .. `Post a comment on pull request {prUrl} with the final review verdict.`,
		"",
		"Include a deferred findings list in the comment. The judge deferred these findings as important but outside the PR's intention:",
		deferredText,
	}, "\n")
end

local function anyNeedsHuman(findings: Findings): boolean
	for _, finding in findings.findings do
		if finding.needsHuman then
			return true
		end
	end
	for _, rec in findings.priorFindingsStatus do
		if rec.needsHuman == true and rec.status == "open" then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Judge session (typed resultSchema, bounded retry)
-- ---------------------------------------------------------------------------

local function runJudge(
	judgeAgent: Agent,
	sessionId: string,
	judgeSessionConfig: { sessionConfig.Entry }?,
	prompt: string
): Findings
	for attempt = 1, DEFAULT_JUDGE_ATTEMPTS do
		local session: Session = judgeAgent:session({ id = sessionId, resultSchema = FINDINGS_SCHEMA })
		sessionConfig.apply(session, judgeSessionConfig)
		local result = session:prompt(prompt)
		local typed = result.result :: Findings?
		session:close()
		if typed ~= nil then
			return typed
		end
		ptah.log(`pr-review judge {sessionId} submitted no typed findings (attempt {attempt}/{DEFAULT_JUDGE_ATTEMPTS})`)
	end
	error(`pr-review judge {sessionId} never submitted typed findings after {DEFAULT_JUDGE_ATTEMPTS} attempts`)
end

local M = {}

function M.new(config: Config): Instance
	local maxIterations = if config.maxIterations ~= nil then config.maxIterations else DEFAULT_MAX_ITERATIONS
	local dryRun = config.dryRun == true
	local work: Agent = config.agent
	local judgeAgent: Agent = config.judgeAgent

	local instance: Instance = {
		review = function(_self: Instance, prUrl: string): Outcome
			if parsePrUrl(prUrl) == nil then
				error(`pr-review: {prUrl} is not a GitHub pull request URL`)
			end
			local persona = config.reviewInstruction or defaultInstruction
			local push: string? = if dryRun
				then nil
				else "Commit the changes and push them to the PR branch so the next review sees them."
			if dryRun then
				ptah.log(`pr-review: dry run — fixes are not pushed to {prUrl}`)
			end

			local existing = readLedger(prUrl)
			local ledger: Ledger
			local commentId: number? = existing.commentId
			local discovery = existing.ledger == nil
			if existing.ledger ~= nil then
				ledger = existing.ledger
			else
				local meta = fetchDiscovery(prUrl)
				ledger = {
					pr = prUrl,
					discoverySha = meta.sha,
					lastReviewedSha = meta.sha,
					intention = meta.intention,
					findings = {},
					families = {},
					resolvedCount = 0,
				}
			end

			local function persist()
				if commentId == nil then
					commentId = createLedgerComment(prUrl, ledger)
				else
					updateLedgerComment(prUrl, commentId, ledger)
				end
			end

			-- The head SHA after a push is the fix's commit; stamp it on the
			-- open blocking findings the fix targeted (dry-run pushes nothing).
			local function recordFixCommit()
				if push == nil then
					return
				end
				local sha = fetchHeadSha(prUrl)
				for _, finding in ledger.findings do
					if finding.severity == "blocking" and finding.status == "open" then
						finding.fixCommit = sha
					end
				end
				persist()
			end

			-- The converged work session posts the verdict comment, including
			-- the deferred findings list. A resume-converge has no new review
			-- prose, so the posted comment text is the verdict.
			local function converge(session: Session, header: string, verdict: string): Outcome
				local posted = session:prompt(buildVerdictPrompt(prUrl, ledger, header))
				session:close()
				persist()
				local finalVerdict = if verdict ~= "" then verdict else posted.text
				return { status = "converged", verdict = finalVerdict, ledger = ledger }
			end

			-- Resume fast paths: no ledger means discovery; an existing ledger
			-- with open blocking findings drives a fix turn; a clean ledger at
			-- the current head converges immediately.
			local iteration = 0
			if not discovery then
				if hasOpenBlocking(ledger) then
					if iteration >= maxIterations - 1 then
						return { status = "non-converged", verdict = "", ledger = ledger }
					end
					local header = `[pr-review iteration {iteration + 1} of {maxIterations}]\n`
					local session: Session = work:session({ id = `pr-review:{iteration}` })
					sessionConfig.apply(session, config.sessionConfig)
					session:prompt(buildFixPrompt(prUrl, ledger, header))
					if push ~= nil then
						session:prompt(header .. push)
					end
					recordFixCommit()
					session:close()
					iteration += 1
				elseif ledger.lastReviewedSha == fetchHeadSha(prUrl) then
					local header = `[pr-review iteration {iteration + 1} of {maxIterations}]\n`
					local session: Session = work:session({ id = `pr-review:converge` })
					sessionConfig.apply(session, config.sessionConfig)
					return converge(session, header, "")
				end
			end

			local isDiscovery = discovery
			local verdict = ""
			while iteration < maxIterations do
				local header = `[pr-review iteration {iteration + 1} of {maxIterations}]\n`
				local reviewedSha = fetchHeadSha(prUrl)
				local session: Session = work:session({ id = `pr-review:{iteration}` })
				sessionConfig.apply(session, config.sessionConfig)

				-- The work session reviews freely in prose; the protocol
				-- fragment (carrying the in-session validation directive) is
				-- always appended.
				local outcome = session:prompt(header .. buildReviewPrompt(persona, prUrl, if isDiscovery then nil else ledger, isDiscovery))
				verdict = outcome.text
				isDiscovery = false

				local findings = runJudge(
					judgeAgent,
					`pr-review-judge:{iteration}`,
					config.judgeSessionConfig,
					buildJudgePrompt(prUrl, verdict, ledger, ledger.intention, config.blockingAdditions)
				)
				applyFindings(ledger, findings)
				ledger.lastReviewedSha = reviewedSha
				persist()

				if not hasOpenBlocking(ledger) then
					return converge(session, header, verdict)
				end

				-- The cap forbids a fix on the final unit: end non-converged
				-- rather than push a fix no review will follow.
				if iteration >= maxIterations - 1 then
					session:close()
					return { status = "non-converged", verdict = verdict, ledger = ledger }
				end

				if anyNeedsHuman(findings) then
					-- The ask's prompt line identifies the loop, the PR URL, and
					-- the iteration state; the details carry the work session's
					-- label, the agent-side ACP session id, and the full review prose,
					-- untruncated.
					local answer = escalate.ask({
						prompt = `pr-review {prUrl}: human input required (iteration {iteration + 1} of {maxIterations})`,
						details = `work session: {session:label()}\nagent session: {session:sessionId()}\n\n{verdict}`,
					})
					if answer.status == "respond" then
						-- The answer is the session's next prompt, verbatim —
						-- no header, no framing: the human is driving the agent.
						-- The human-guided fix gets the same commit-and-push step
						-- as any fix (gated by dry-run), and the iteration counts
						-- against the cap.
						session:prompt(answer.text)
						if push ~= nil then
							session:prompt(header .. push)
						end
						recordFixCommit()
						session:close()
						iteration += 1
					elseif answer.status == "abort" then
						session:close()
						error(`pr-review: human aborted escalation (iteration {iteration + 1} of {maxIterations})`)
					else
						-- No ask provider served the request: today's failure,
						-- byte-identical.
						session:close()
						error(
							`pr-review: human input is required to resolve the findings (iteration {iteration + 1} of {maxIterations})`
						)
					end
				else
					-- Batched fix turn: all open blocking findings, by root
					-- cause, followed by commit-and-push (gated by dry-run).
					session:prompt(buildFixPrompt(prUrl, ledger, header))
					if push ~= nil then
						session:prompt(header .. push)
					end
					recordFixCommit()
					session:close()
					iteration += 1
				end
			end
			return { status = "non-converged", verdict = verdict, ledger = ledger }
		end,
	}
	return instance
end

return M
