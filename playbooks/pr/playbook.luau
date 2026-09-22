--!strict
-- PR review playbook: two operations over one shared review-pass atom,
-- against a pull request. `review` runs exactly one pass — a discovery
-- review when no ledger exists, a delta review otherwise — unconditionally,
-- and never fixes; `reviewFixLoop` composes passes with batched fix turns
-- under a budget, converging when no open blocking findings remain. Repo
-- specifics (reviewer persona, blocking taxonomy, dry-run gating) arrive as
-- config; the PR URL is the sole repository context. The work session
-- reviews freely in prose following its persona; a typed judge session (a
-- `resultSchema` result) is the schema boundary that converts that prose
-- into structured findings, reconciles them with the ledger, and computes
-- the outcome status (`openBlocking == 0`). The operations' cross-run memory
-- is a ledger stored in a dedicated PR comment, updated in place, and
-- resumed automatically by the loop. See README.md for the two operations,
-- the three-layer instruction contract, and the declared environment
-- requirements.
--
-- Pass shape (the atom both operations run — this playbook's own policy over
-- std/predicate's typed-result pattern):
--   * a discovery pass (full-PR review) when no ledger exists, then delta
--     reviews against the ledger's `lastReviewedSha`; a lone `review` pass
--     runs unconditionally — no ledger state gates or skips it;
--   * a typed judge converts the prose into findings and reconciles the
--     ledger findings, flagging `needsHuman`;
--   * the pass never fixes, commits, or pushes — it applies the findings,
--     advances the ledger's `lastReviewedSha`, and persists;
--   * the loop then fixes when open blocking findings remain and budget
--     remains, in one batched fix turn by root cause, followed by
--     commit-and-push (gated by dry-run); an open blocking finding carrying
--     `needsHuman` is fixed autonomously like any other — the loop never
--     asks a human (the PR itself, reviewed at merge time, is its human
--     checkpoint; the flag is report-only);
--   * a fix is issued only when budget remains, so every push is followed
--     by at least one review pass;
--   * every returned terminal outcome of either operation posts a PR review
--     report: a reporter agent authors the body, and the playbook prepends
--     a deterministic status line and posts the marked comment.

local gh = require("../../std/gh")
local sessionConfig = require("../../std/session-config")
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
	-- The judge's latest determination that resolving this finding needs a
	-- human: recorded when the finding is filed, updated when a later
	-- reconciliation revisits it, never cleared — there is no mid-loop
	-- human decision to supersede it. Report-only: it never gates, pauses,
	-- or fails the loop; it renders on open findings' lines for the human
	-- reviewing the PR.
	needsHuman: boolean,
	-- The commit that carried the fix, once a fix turn has pushed one.
	fixCommit: string?,
}

-- The playbook-owned ledger: PR identity, the discovery and last-reviewed
-- SHAs, the PR's intention, the findings (resolved findings retained with
-- status `fixed`), the family table, and the count of findings resolved
-- once verified clean. A legacy `decisions` record (the retired ask path's
-- writer) is dropped on read and never written.
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
	-- never gates convergence. (`accepted` is a legacy status no judge
	-- writes: its only writer was the retired adjudication path.)
	status: "open" | "deferred",
	-- A short description of the issue (one line).
	title: string,
}

-- The judge's reconciliation of one ledger finding it was shown.
-- `deferred` means still deferred: a no-op confirmation that reports a
-- recurrence against the existing id instead of refiling it.
export type JudgeReconciliation = {
	id: string,
	status: "resolved" | "open" | "deferred",
	evidence: string?,
	-- Set when resolving a still-open finding needs a human decision.
	needsHuman: boolean?,
}

-- The judge session's typed result.
export type Findings = {
	findings: { JudgeFinding },
	priorFindingsStatus: { JudgeReconciliation },
}

-- The reporter session's typed result: the report body. The playbook prepends
-- the deterministic status line, so it is not part of this contract.
export type Report = {
	report: string,
}

-- Either operation's outcome: outcomes as data, so the caller's script can
-- gate its own post-operation steps (CI, gates) on the end state. `verdict`
-- is always a review pass's prose for `review` (the pass always runs); the
-- `""` case only ever arises from the loop's resume fast paths, which run
-- no pass.
export type Outcome = {
	status: "converged" | "non-converged",
	verdict: string,
	ledger: Ledger,
	-- The posted PR review report text: the playbook's deterministic status
	-- line followed by the reporter's authored body.
	report: string,
}

export type Config = {
	-- Work agent handle reviewing and fixing the PR. The work session never
	-- posts to the PR; the playbook posts the report.
	agent: Agent,
	-- Judge agent handle for the typed findings session. Required: the loop's
	-- convergence is computed from the judge's typed output, and there is no
	-- prose-parsing fallback.
	judgeAgent: Agent,
	-- Reporter agent handle for the PR review report's typed body session.
	-- Required: the reporter authors the report; the playbook prepends the
	-- status line and posts the marked comment.
	reporterAgent: Agent,
	-- Ordered session-config entries applied to every work session the
	-- playbook creates: each review/fix iteration's session.
	sessionConfig: { sessionConfig.Entry }?,
	-- Ordered session-config entries applied to every judge session.
	judgeSessionConfig: { sessionConfig.Entry }?,
	-- Ordered session-config entries applied to every reporter session.
	reporterSessionConfig: { sessionConfig.Entry }?,
	-- Absolute working directory for every session this playbook
	-- creates (review/fix, judge, and reporter sessions alike). Nil
	-- keeps today's behavior: sessions run in the invocation directory.
	-- The playbook stays git-agnostic — this is just a directory;
	-- provisioning it is the calling shim's business.
	workingDir: string?,
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
	-- reviewFixLoop only — inert for `review` (a pass never pushes).
	dryRun: boolean?,
	-- Convergence cap (default 8) over loop units; a fix turn is issued only
	-- when budget remains. reviewFixLoop only — inert for `review` (a pass
	-- never loops).
	maxIterations: number?,
}

-- The outcome status both operations compute from the ledger's open blocking
-- count.
type OutcomeStatus = "converged" | "non-converged"

-- One operation invocation's shared machinery, extracted so the pass cannot
-- drift between the two operations: in-place ledger persistence, the
-- review-pass primitive, and the terminal report step.
type Operation = {
	persist: () -> (),
	-- The review-pass primitive: prompt (a caller-supplied header plus the
	-- persona/protocol review prompt) → work session → typed judge →
	-- applyFindings → persist. Returns the pass's verdict prose, the
	-- outcome status implied by the open blocking count, and the still-open
	-- work session — the loop issues its fix turn in the same session; a
	-- lone pass closes it.
	reviewPass: (params: {
		isDiscovery: boolean,
		header: string,
		workSessionId: string,
		judgeSessionId: string,
	}) -> (string, OutcomeStatus, Session),
	-- The single terminal report step: every returning outcome routes
	-- through it, after the ledger is persisted. The reporter authors the
	-- body, the playbook prepends the deterministic status line and posts
	-- the marked comment, and the posted text is the outcome's report.
	-- `passes` is the operation's pass count: 1 for `review`; the loop's
	-- completed units for `reviewFixLoop` (0 when a resume ran no pass).
	finish: (status: OutcomeStatus, verdictText: string, prose: string?, passes: number) -> Outcome,
}

export type Instance = {
	-- Run exactly one review pass against one pull request (the PR URL is
	-- per-call data, not config): a discovery pass when no ledger exists, a
	-- delta review otherwise — unconditionally; no ledger state gates or
	-- skips it. The pass never fixes, commits, or pushes. Returns the typed
	-- outcome: `verdict` is always the pass prose; `status` is `converged`
	-- when no open blocking findings remain after the pass.
	review: (self: Instance, prUrl: string) -> Outcome,
	-- Run the convergent review→fix loop against one pull request: review
	-- passes composed with batched fix turns under the `maxIterations`
	-- budget, resuming from an existing ledger automatically, never asking a
	-- human. Returns the typed outcome.
	reviewFixLoop: (self: Instance, prUrl: string) -> Outcome,
}

local DEFAULT_MAX_ITERATIONS = 8
local DEFAULT_JUDGE_ATTEMPTS = 3
local DEFAULT_REPORTER_ATTEMPTS = 3
local LEDGER_MARKER = "<!-- ptah:pr-review-ledger -->"
local REPORT_MARKER = "<!-- ptah:pr-review-report -->"
-- The report's *Findings resolved* list caps at the 50 most recent entries;
-- the ledger still retains every entry.
local RESOLVED_LIST_CAP = 50

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
					status = { type = "string", enum = { "open", "deferred" } },
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
					status = { type = "string", enum = { "resolved", "open", "deferred" } },
					evidence = { type = "string" },
					needsHuman = { type = "boolean" },
				},
				required = { "id", "status" },
			},
		},
	},
	required = { "findings", "priorFindingsStatus" },
}

-- The reporter session's result contract: the single report-body field.
local REPORT_SCHEMA: { [string]: any } = {
	type = "object",
	additionalProperties = false,
	properties = {
		report = { type = "string" },
	},
	required = { "report" },
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
	if type(value) ~= "table" or type(value.findings) ~= "table" then
		return nil
	end
	-- Legacy ledgers predate `needsHuman`, and ledgers from the retired ask
	-- path carry a decisions record: read tolerantly (a finding without the
	-- flag is treated as not needing a human; `accepted` findings stay
	-- terminal) and drop the decisions record, so no persist ever re-writes
	-- it. The flag is written on the next persist.
	value.decisions = nil
	local ledger = value :: Ledger
	for _, finding in ledger.findings do
		if type(finding) == "table" then
			finding.needsHuman = finding.needsHuman == true
		end
	end
	return ledger
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

-- List the PR's issue comments: the transport behind both markers.
local function listComments(prUrl: string): { any }
	local ref = parsePrUrl(prUrl)
	if ref == nil then
		error(`pr-review: {prUrl} is not a GitHub pull request URL`)
	end
	local path = `/repos/{ref.owner}/{ref.repo}/issues/{ref.number}/comments`
	local outcome = gh.run({ "api", "--paginate", "--slurp", path }, { json = true })
	if not outcome.ok then
		error(`pr-review: could not read PR comments for {prUrl}: {outcome.stderr}`)
	end
	return collectComments(outcome.json)
end

local function readLedger(prUrl: string): { ledger: Ledger?, commentId: number? }
	for _, comment in listComments(prUrl) do
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

-- ---------------------------------------------------------------------------
-- Report transport (std/gh): the ledger's marker-and-edit lifecycle
-- ---------------------------------------------------------------------------

local function reportBody(text: string): string
	return REPORT_MARKER .. "\n\n" .. text .. "\n"
end

local function readReportCommentId(prUrl: string): number?
	for _, comment in listComments(prUrl) do
		local body = comment.body
		if type(body) == "string" and string.find(body, REPORT_MARKER, 1, true) ~= nil then
			return commentDatabaseId(comment)
		end
	end
	return nil
end

local function createReportComment(prUrl: string, text: string): number?
	local ref = parsePrUrl(prUrl)
	if ref == nil then
		error(`pr-review: {prUrl} is not a GitHub pull request URL`)
	end
	local path = `/repos/{ref.owner}/{ref.repo}/issues/{ref.number}/comments`
	local outcome = gh.run({ "api", "--method", "POST", path, "-f", `body={reportBody(text)}` }, { json = true })
	if not outcome.ok then
		error(`pr-review: could not create the report comment on {prUrl}: {outcome.stderr}`)
	end
	local id = outcome.json.id
	if type(id) == "number" then
		return id
	end
	return nil
end

local function updateReportComment(prUrl: string, commentId: number, text: string)
	local ref = parsePrUrl(prUrl)
	if ref == nil then
		error(`pr-review: {prUrl} is not a GitHub pull request URL`)
	end
	local path = `/repos/{ref.owner}/{ref.repo}/issues/comments/{commentId}`
	local outcome = gh.run({ "api", "--method", "PATCH", path, "-f", `body={reportBody(text)}` }, { json = true })
	if not outcome.ok then
		error(`pr-review: could not update the report comment on {prUrl}: {outcome.stderr}`)
	end
end

-- Read/create/update in one step: a re-run edits the existing report in place
-- rather than appending a second comment.
local function postReport(prUrl: string, text: string)
	local existingId = readReportCommentId(prUrl)
	if existingId == nil then
		createReportComment(prUrl, text)
	else
		updateReportComment(prUrl, existingId, text)
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

-- Load the ledger both operations start from: an existing ledger comment is
-- resumed; its absence starts a fresh discovery ledger (the discovery SHA,
-- the `lastReviewedSha`, and the PR's intention captured at discovery).
-- Returns the ledger, its comment id (nil when no comment exists — kept even
-- when the body fails to parse, so a persist repairs it in place), and
-- whether this invocation is a discovery.
local function openLedger(prUrl: string): (Ledger, number?, boolean)
	local existing = readLedger(prUrl)
	if existing.ledger ~= nil then
		return existing.ledger, existing.commentId, false
	end
	local meta = fetchDiscovery(prUrl)
	return {
		pr = prUrl,
		discoverySha = meta.sha,
		lastReviewedSha = meta.sha,
		intention = meta.intention,
		findings = {},
		families = {},
		resolvedCount = 0,
	}, existing.commentId, true
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

local function openBlockingCount(ledger: Ledger): number
	local count = 0
	for _, finding in ledger.findings do
		if finding.severity == "blocking" and finding.status == "open" then
			count += 1
		end
	end
	return count
end

local function hasOpenBlocking(ledger: Ledger): boolean
	return openBlockingCount(ledger) > 0
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
	-- Deferred findings ride along with their ids: a recurrence is reported
	-- against the existing id (still deferred) instead of refilled as a
	-- duplicate.
	local deferredFindings: { string } = {}
	for _, finding in ledger.findings do
		if finding.status == "deferred" then
			table.insert(
				deferredFindings,
				`{finding.id} ({finding.severity}, family {finding.family}): {finding.title}`
			)
		end
	end
	if #deferredFindings > 0 then
		table.insert(
			lines,
			`- deferred findings (still deferred — report a recurrence against the existing id): {table.concat(deferredFindings, "; ")}`
		)
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

-- The ledger finding an id names, or nil when the id matches no entry —
-- the join behind reconciliation's inert handling of unknown ids.
local function ledgerFindingById(ledger: Ledger, id: string): LedgerFinding?
	for _, finding in ledger.findings do
		if finding.id == id then
			return finding
		end
	end
	return nil
end

-- Reconcile the judge's typed output into the ledger. A finding the judge
-- verified resolved in a later pass is retained as a terminal one-line entry
-- with status `fixed` (its fix commit preserved) and the resolved count still
-- advances; `fixed` entries no longer participate in reconciliation, gate
-- convergence, or appear in the open-findings summary. A still-deferred
-- reconciliation is a no-op confirmation: the entry stays, no duplicate is
-- filed. Every reconciliation record that revisits an open or deferred
-- finding updates its `needsHuman` flag — the judge's latest determination
-- wins (the flag never clears; there is no mid-loop human decision to
-- supersede it). The judge's new findings are appended with fresh ids; the
-- filed findings are returned in filing order (open blocking ones drive the
-- fix turn — `needsHuman` never gates).
local function applyFindings(ledger: Ledger, findings: Findings): { LedgerFinding }
	for _, rec in findings.priorFindingsStatus do
		local finding = ledgerFindingById(ledger, rec.id)
		if finding == nil then
			continue -- an unknown id is inert: never fixed, never flagged
		end
		if finding.status == "open" or finding.status == "deferred" then
			finding.needsHuman = rec.needsHuman == true
		end
		if rec.status == "resolved" and finding.status == "open" then
			finding.status = "fixed"
			ledger.resolvedCount += 1
		end
	end

	local filed: { LedgerFinding } = {}
	local nextId = nextFindingId(ledger)
	for _, judgeFinding in findings.findings do
		local finding: LedgerFinding = {
			id = `f{nextId}`,
			title = judgeFinding.title,
			family = judgeFinding.family,
			severity = judgeFinding.severity,
			validation = judgeFinding.validation,
			status = judgeFinding.status,
			needsHuman = judgeFinding.needsHuman,
			fixCommit = nil,
		}
		table.insert(ledger.findings, finding)
		table.insert(filed, finding)
		nextId += 1
		if not contains(ledger.families, judgeFinding.family) then
			table.insert(ledger.families, judgeFinding.family)
		end
	end
	return filed
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
		"- A recurrence of a deferred ledger finding is still deferred: report it against that finding's id with status \"deferred\", never as a new finding.",
		"- For every open or deferred ledger finding, report in priorFindingsStatus whether it is resolved (with evidence), still open, or still deferred.",
		"- Set needsHuman true only on an open blocking finding that rests on an operator-owned decision — one the agent has no authority to take — that a human should examine at review. Never set needsHuman on a deferred or non-blocking finding: a human-worthy non-blocking concern belongs in the review prose.",
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

-- Render one ledger finding as a one-line entry (the fixing commit, when
-- present, travels with it; a persisted `needsHuman` flag renders on open
-- findings' lines — a pointer for the human reviewing the PR, never a
-- gate).
local function renderFinding(finding: LedgerFinding): string
	local flag = if finding.needsHuman and finding.status == "open" then ", needs human" else ""
	local fix = if finding.fixCommit ~= nil and finding.fixCommit ~= "" then `, fix {finding.fixCommit}` else ""
	return `- {finding.id} ({finding.severity}, family {finding.family}, validation {finding.validation}{flag}{fix}): {finding.title}`
end

-- The full ledger render handed to the reporter: every status group
-- (including retained `fixed` entries), the intention, the family table, the
-- operation's pass count, the discovery/last-reviewed commits, and the
-- resolved count. The ledger is the durable whole-operation memory, so the
-- report is fully derivable from it (plus the pass count, which lives
-- outside the ledger).
local function renderLedger(ledger: Ledger, passes: number): string
	local lines: { string } = {
		"### Intention",
		ledger.intention,
		"",
		"### Review state",
		`- passes: {passes}`,
		`- discovery commit: {ledger.discoverySha}`,
		`- last reviewed commit: {ledger.lastReviewedSha}`,
		`- resolved count (all time): {ledger.resolvedCount}`,
	}
	if #ledger.families > 0 then
		table.insert(lines, `- families: {table.concat(ledger.families, ", ")}`)
	else
		table.insert(lines, "- families: none")
	end

	local function group(label: string, predicate: (LedgerFinding) -> boolean)
		table.insert(lines, "")
		table.insert(lines, `### {label}`)
		local count = 0
		for _, finding in ledger.findings do
			if predicate(finding) then
				table.insert(lines, renderFinding(finding))
				count += 1
			end
		end
		if count == 0 then
			table.insert(lines, "(none)")
		end
	end
	group("Open blocking", function(f: LedgerFinding): boolean
		return f.status == "open" and f.severity == "blocking"
	end)
	group("Open non-blocking", function(f: LedgerFinding): boolean
		return f.status == "open" and f.severity == "non-blocking"
	end)
	group("Findings resolved (fixed)", function(f: LedgerFinding): boolean
		return f.status == "fixed"
	end)
	group("Deferred", function(f: LedgerFinding): boolean
		return f.status == "deferred"
	end)
	group("Accepted", function(f: LedgerFinding): boolean
		return f.status == "accepted"
	end)
	return table.concat(lines, "\n")
end

-- The section contract the reporter authors the body under. The playbook
-- prepends the deterministic status line, so the reporter is told not to
-- write one. The *Findings resolved* list is capped while the ledger keeps
-- every entry.
local function sectionContract(status: "converged" | "non-converged"): string
	local lines: { string } = {
		"Author the report body under exactly these sections, in this order:",
	}
	if status == "non-converged" then
		table.insert(lines, "- Open blocking: every open blocking finding, most important first.")
	end
	table.insert(lines, "- What this PR does: the PR's intention in a short paragraph.")
	table.insert(
		lines,
		`- Findings resolved: one line per resolved finding, most recent first. List at most the {RESOLVED_LIST_CAP} most recent entries; when more resolved entries exist, append a final line reading "…and N earlier omitted", where N is the number not listed.`
	)
	table.insert(lines, "- Open non-blocking: one line per open non-blocking finding, with its ledger id and title.")
	table.insert(
		lines,
		"- Deferred: one line per deferred finding, noting it is important but outside the PR's intention."
	)
	table.insert(
		lines,
		"- Accepted: one line per accepted finding; accepted findings are legacy entries (a retired mid-loop ask produced them) — annotate them as maintainer decisions."
	)
	table.insert(
		lines,
		"- Review summary: the pass count, the discovery and last-reviewed commits, and the family table."
	)
	table.insert(lines, "- Do not add a status line; the playbook prepends one.")
	return table.concat(lines, "\n")
end

-- The reporter prompt: the full ledger render, the terminal status, the last
-- review pass's prose (or an explicit no-prose marker when the operation ran
-- no review pass), and the section contract. Operation-agnostic: `passes` is
-- 1 for a lone `review` pass, the loop's completed units for
-- `reviewFixLoop`.
local function buildReporterPrompt(
	prUrl: string,
	ledger: Ledger,
	status: "converged" | "non-converged",
	prose: string?,
	passes: number
): string
	local proseSection: string
	if prose ~= nil and prose ~= "" then
		proseSection = prose
	else
		proseSection = "(no review prose for this run: render the report from the ledger alone)"
	end
	return table.concat({
		`Write the PR review report body for {prUrl}.`,
		"",
		`The operation's terminal status is {status}.`,
		"",
		"## Full ledger",
		renderLedger(ledger, passes),
		"",
		"## Last review pass prose",
		proseSection,
		"",
		"## Section contract",
		sectionContract(status),
	}, "\n")
end

-- The deterministic status line: composed by the playbook from the ledger so
-- the report's convergence claim is never agent-authored.
local function statusLine(status: "converged" | "non-converged", ledger: Ledger): string
	local open = openBlockingCount(ledger)
	local noun = if open == 1 then "finding" else "findings"
	return `**PR review report — {status}** ({open} open blocking {noun})`
end

-- ---------------------------------------------------------------------------
-- Judge session (typed resultSchema, bounded retry)
-- ---------------------------------------------------------------------------

local function runJudge(
	judgeAgent: Agent,
	sessionId: string,
	judgeSessionConfig: { sessionConfig.Entry }?,
	cwd: string?,
	prompt: string
): Findings
	for attempt = 1, DEFAULT_JUDGE_ATTEMPTS do
		local session: Session = judgeAgent:session({ id = sessionId, cwd = cwd, resultSchema = FINDINGS_SCHEMA })
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

-- ---------------------------------------------------------------------------
-- Reporter session (typed resultSchema, bounded retry)
-- ---------------------------------------------------------------------------

local function runReporter(
	reporterAgent: Agent,
	sessionId: string,
	reporterSessionConfig: { sessionConfig.Entry }?,
	cwd: string?,
	prompt: string
): string
	for attempt = 1, DEFAULT_REPORTER_ATTEMPTS do
		local session: Session = reporterAgent:session({ id = sessionId, cwd = cwd, resultSchema = REPORT_SCHEMA })
		sessionConfig.apply(session, reporterSessionConfig)
		local result = session:prompt(prompt)
		local typed = result.result :: Report?
		session:close()
		if typed ~= nil then
			return typed.report
		end
		ptah.log(
			`pr-review reporter {sessionId} submitted no typed report (attempt {attempt}/{DEFAULT_REPORTER_ATTEMPTS})`
		)
	end
	error(`pr-review reporter {sessionId} never submitted a typed report after {DEFAULT_REPORTER_ATTEMPTS} attempts`)
end

local M = {}

function M.new(config: Config): Instance
	local maxIterations = if config.maxIterations ~= nil then config.maxIterations else DEFAULT_MAX_ITERATIONS
	local dryRun = config.dryRun == true
	local work: Agent = config.agent
	local judgeAgent: Agent = config.judgeAgent
	local reporterAgent: Agent = config.reporterAgent
	local persona = config.reviewInstruction or defaultInstruction

	-- One operation invocation's shared machinery, extracted so the pass
	-- cannot drift between the two operations: the ledger and its comment
	-- id, in-place persistence, the review-pass primitive, and the terminal
	-- report step. `review` runs the primitive once; `reviewFixLoop` runs it
	-- once per unit.
	local function operation(prUrl: string, ledger: Ledger, commentId: number?): Operation
		local function persist()
			if commentId == nil then
				commentId = createLedgerComment(prUrl, ledger)
			else
				updateLedgerComment(prUrl, commentId, ledger)
			end
		end

		-- The single terminal report step: every returning outcome routes
		-- through it, after the ledger is persisted and the work session
		-- (if any) is closed. The reporter authors the body, the playbook
		-- prepends the deterministic status line and posts the marked
		-- comment, and the posted text is the outcome's report. `passes` is
		-- the operation's pass count (1 for a lone pass; the loop's
		-- completed units, 0 when a resume ran no pass).
		local function finish(status: OutcomeStatus, verdictText: string, prose: string?, passes: number): Outcome
			persist()
			local body = runReporter(
				reporterAgent,
				"pr-review-reporter",
				config.reporterSessionConfig,
				config.workingDir,
				buildReporterPrompt(prUrl, ledger, status, prose, passes)
			)
			local posted = statusLine(status, ledger) .. "\n\n" .. body
			postReport(prUrl, posted)
			return { status = status, verdict = verdictText, ledger = ledger, report = posted }
		end

		-- The review-pass primitive shared by both operations: prompt with a
		-- caller-supplied header (the loop's `[pr-review iteration N of M]`,
		-- the lone pass's `[pr-review pass]`) → work session → typed judge →
		-- applyFindings → persist. Returns the pass's verdict prose, the
		-- outcome status implied by the open blocking count, and the
		-- still-open work session — the loop issues its fix turn in the same
		-- session; a lone pass closes it.
		local function reviewPass(params: {
			isDiscovery: boolean,
			header: string,
			workSessionId: string,
			judgeSessionId: string,
		}): (string, OutcomeStatus, Session)
			local reviewedSha = fetchHeadSha(prUrl)
			local session: Session = work:session({ id = params.workSessionId, cwd = config.workingDir })
			sessionConfig.apply(session, config.sessionConfig)

			-- The work session reviews freely in prose; the protocol
			-- fragment (carrying the in-session validation directive) is
			-- always appended.
			local outcome = session:prompt(
				params.header
					.. buildReviewPrompt(persona, prUrl, if params.isDiscovery then nil else ledger, params.isDiscovery)
			)
			local verdict = outcome.text

			local findings = runJudge(
				judgeAgent,
				params.judgeSessionId,
				config.judgeSessionConfig,
				config.workingDir,
				buildJudgePrompt(prUrl, verdict, ledger, ledger.intention, config.blockingAdditions)
			)
			applyFindings(ledger, findings)
			ledger.lastReviewedSha = reviewedSha
			persist()
			local status: OutcomeStatus = if hasOpenBlocking(ledger) then "non-converged" else "converged"
			return verdict, status, session
		end

		return {
			persist = persist,
			finish = finish,
			reviewPass = reviewPass,
		}
	end

	local instance: Instance = {
		-- One unconditional review pass: discovery when no ledger exists, a
		-- delta review otherwise — no ledger state gates or skips it, and no
		-- fix turn ever follows it (deleting the ledger is the re-review
		-- escape hatch).
		review = function(_self: Instance, prUrl: string): Outcome
			if parsePrUrl(prUrl) == nil then
				error(`pr-review: {prUrl} is not a GitHub pull request URL`)
			end

			local ledger, commentId, discovery = openLedger(prUrl)
			local ctx = operation(prUrl, ledger, commentId)

			local verdict: string, status: OutcomeStatus, session: Session = ctx.reviewPass({
				isDiscovery = discovery,
				header = "[pr-review pass]\n",
				workSessionId = "pr-review-pass",
				judgeSessionId = "pr-review-pass-judge",
			})
			session:close()
			return ctx.finish(status, verdict, verdict, 1)
		end,

		-- The convergent review→fix loop over the same pass primitive, with
		-- its resume fast paths, batched fix turns, budget rule, and
		-- never-ask behavior.
		reviewFixLoop = function(_self: Instance, prUrl: string): Outcome
			if parsePrUrl(prUrl) == nil then
				error(`pr-review: {prUrl} is not a GitHub pull request URL`)
			end
			local push: string? = if dryRun
				then nil
				else "Commit the changes and push them to the PR branch so the next review sees them."
			if dryRun then
				ptah.log(`pr-review: dry run — fixes are not pushed to {prUrl}`)
			end

			local ledger, commentId, discovery = openLedger(prUrl)
			local ctx = operation(prUrl, ledger, commentId)

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
				ctx.persist()
			end

			-- Loop progress: the count of completed units. A review pass that
			-- just ran is `iteration + 1`; a resume that runs no pass reports
			-- 0.
			local iteration = 0

			-- Resume fast paths: an existing ledger with open blocking
			-- findings drives a fix turn; a clean ledger at the current head
			-- converges immediately.
			if not discovery then
				if hasOpenBlocking(ledger) then
					if iteration >= maxIterations - 1 then
						-- Resumed ledger already at the cap: no review pass runs,
						-- so the report is rendered from the ledger alone.
						return ctx.finish("non-converged", "", nil, 0)
					end
					local header = `[pr-review iteration {iteration + 1} of {maxIterations}]\n`
					local session: Session = work:session({ id = `pr-review:{iteration}`, cwd = config.workingDir })
					sessionConfig.apply(session, config.sessionConfig)
					session:prompt(buildFixPrompt(prUrl, ledger, header))
					if push ~= nil then
						session:prompt(header .. push)
					end
					recordFixCommit()
					session:close()
					iteration += 1
				elseif ledger.lastReviewedSha == fetchHeadSha(prUrl) then
					-- Clean ledger at the current head: no work session runs; the
					-- report goes straight to the reporter (no review prose).
					return ctx.finish("converged", "", nil, 0)
				end
			end

			local isDiscovery = discovery
			local verdict = ""
			while iteration < maxIterations do
				local header = `[pr-review iteration {iteration + 1} of {maxIterations}]\n`
				local passVerdict, status, session = ctx.reviewPass({
					isDiscovery = isDiscovery,
					header = header,
					workSessionId = `pr-review:{iteration}`,
					judgeSessionId = `pr-review-judge:{iteration}`,
				})
				verdict = passVerdict
				isDiscovery = false

				if status == "converged" then
					session:close()
					return ctx.finish("converged", verdict, verdict, iteration + 1)
				end

				-- The cap forbids a fix on the final unit: end non-converged
				-- rather than push a fix no review will follow.
				if iteration >= maxIterations - 1 then
					session:close()
					return ctx.finish("non-converged", verdict, verdict, iteration + 1)
				end

				-- Batched fix turn: all open blocking findings, by root cause,
				-- followed by commit-and-push (gated by dry-run). An open
				-- blocking finding carrying `needsHuman` is fixed autonomously
				-- like any other: the flag is report-only — the loop never
				-- asks, and the next review pass re-judges the fix.
				session:prompt(buildFixPrompt(prUrl, ledger, header))
				if push ~= nil then
					session:prompt(header .. push)
				end
				recordFixCommit()
				session:close()
				iteration += 1
			end
			return ctx.finish("non-converged", verdict, if verdict ~= "" then verdict else nil, iteration)
		end,
	}
	return instance
end

return M
