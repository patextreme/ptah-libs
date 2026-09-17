--!strict
-- Issue pickup playbook: scan a repo-configured queue label and claim one
-- eligible issue for the calling script to work. Agent-free by design: the
-- intelligence is the claim protocol (a marked comment plus earliest-wins
-- read-back), not a prompt, so there is nothing to configure but the label
-- vocabulary. See README.md in this directory for the declared environment
-- requirements and the claim protocol summary;
-- docs/adr/0002-issue-claims-earliest-marker-wins.md for the claim protocol
-- docs/adr/0003-pickup-scoped-to-own-assignments.md and
-- docs/adr/0004-pickup-eligible-unless-foreign-assigned.md for the
-- assignment scope.
--
-- The scan reads every open issue carrying the queue label through the REST
-- issues endpoint with `--paginate --slurp` (the `gh issue list` window is
-- capped and newest-first, so it cannot carry "oldest first" for a queue
-- larger than one page). It drops pull requests (they share the endpoint)
-- and applies the three-signal eligibility filter: the queue label is
-- present, the issue is not foreign-assigned (no assignees, or the
-- authenticated account among them), and the issue carries no claim marker
-- comment. The client-side foreign-assignment check is the only assignment
-- signal: the issues endpoint's `assignee` term is a single value and
-- cannot express "none or mine" as a union, so the scan never narrows by
-- assignee server-side. `claimedLabel`, when configured, is added on claim
-- for human-legible queue state only — it is never a gate and never
-- narrows the candidate set.
--
-- A claim is a dedicated comment carrying the `<!-- ptah:issue-claim -->`
-- marker plus one fixed legible sentence (a bare marker renders as an empty
-- comment), with no protocol data fields: the posting gh account and the
-- comment's platform timestamps carry identity and order. Because GitHub
-- offers no atomic test-and-set, a claim is verified by reading the claims
-- back after posting: the winner is the earliest claim comment by the
-- platform creation timestamp, with the numeric REST comment id as
-- tie-break (the lowest id wins, since ids increase monotonically with
-- creation; the GraphQL node id is not orderable). Nothing but the marker
-- is written before the read-back confirms the win: only a winner then
-- self-assigns and, when configured, adds `claimedLabel`. A loser leaves
-- its own losing marker in place and moves on — it writes nothing further —
-- so a requeue deletes every claim marker on the issue, never just the
-- winner's.

local gh = require("../../std/gh")

-- The queue label is required with no default: the label vocabulary is the
-- repository's, never the playbook's.
export type Config = {
	queueLabel: string,
	-- Added on claim for human-legible queue state only. Never reads it as a
	-- gate, and never removes the queue label (a human's readiness
	-- assertion).
	claimedLabel: string?,
}

-- The pickup brief: enough for the calling script to drive the work without
-- re-fetching the issue. `claimCommentId` is the winning claim's numeric
-- REST comment id.
export type Brief = {
	number: number,
	url: string,
	title: string,
	body: string,
	claimCommentId: number,
}

export type Claimed = {
	status: "claimed",
	brief: Brief,
}

export type NoEligibleIssue = {
	status: "no-eligible-issue",
	-- The scan summary: how many issues were examined under the full
	-- eligibility scope — carrying the queue label and not assigned to
	-- another account (pull requests dropped) — before none proved
	-- eligible. `scanned: 0` means every labeled issue in the queue is
	-- assigned to other accounts (or the queue is empty). Not the whole
	-- labeled queue: foreign-assigned issues never enter the count.
	scanned: number,
}

-- Outcomes as data, discriminated on `status`. A scan that finds no eligible
-- issue returns `no-eligible-issue` rather than raising.
export type Outcome = Claimed | NoEligibleIssue

export type Instance = {
	-- Claim the oldest eligible issue (no argument), or claim a specific
	-- issue by number only if eligible. An explicit miss (missing queue
	-- label, assigned to another account, already claimed, or lost
	-- contention) raises with the reason.
	pickUp: (self: Instance, number: number?) -> Outcome,
}

-- The wire marker. Read-old-write-new is a migration if this ever changes
-- (ADR 0001's wire-freeze principle).
local MARKER = "<!-- ptah:issue-claim -->"
-- Marker plus one fixed legible sentence: no protocol fields (the posting
-- account is the identity). The sentence keeps the claim human-visible.
local CLAIM_BODY = MARKER .. "\n\nClaimed by a ptah run for automated pickup.\n"

local ERROR_PREFIX = "issue-pickup"

-- Resolve the authenticated gh account's login. One identity serves both
-- the foreign-assignment check and the post-win self-assign. The caller
-- memoizes this per instance. A failed resolution raises through the
-- transport's outcome, its stderr in the error.
local function resolveLogin(): string
	local outcome = gh.run({ "api", "--method", "GET", "/user" }, { json = true })
	if not outcome.ok then
		error(`{ERROR_PREFIX}: could not resolve the authenticated gh account: {outcome.stderr}`)
	end
	local entry: any = outcome.json
	if type(entry) ~= "table" or type(entry.login) ~= "string" or entry.login == "" then
		error(`{ERROR_PREFIX}: could not resolve the authenticated gh account: no login in the /user response`)
	end
	return entry.login
end

-- One scanned candidate: the brief fields plus the two client-side
-- eligibility checks (the label and the foreign-assignment check).
type Candidate = {
	number: number,
	url: string,
	title: string,
	body: string,
	hasQueueLabel: boolean,
	-- The issue is assigned only to other accounts: it has assignees and
	-- none of them is the authenticated account. No assignees is not
	-- foreign, and a teammate cc'd alongside the account is not foreign
	-- (ADR 0003's among-not-sole rule). The only assignment signal: the
	-- scan does not narrow by assignee server-side.
	assignedElsewhere: boolean,
}

-- One claim attempt's result. `ineligible` and `lost` both mean "not this
-- issue": scan mode moves to the next candidate, explicit mode raises with
-- the reason (only the claim-marker signal needs a comments read).
type Attempt = {
	status: "claimed",
	brief: Brief,
} | {
	status: "ineligible",
	reason: "label" | "assigned-elsewhere" | "claimed",
} | {
	status: "lost",
}

-- Flatten `gh api --paginate --slurp` output: a slurped response is an array
-- of pages, each page an array of entries; a flat response is an array of
-- entries. An issue entry always carries `number`, a page never does.
local function flattenPages(raw: any): { any }
	local out: { any } = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, entry in raw do
		if type(entry) == "table" and entry.number == nil then
			for _, item in entry do
				table.insert(out, item)
			end
		else
			table.insert(out, entry)
		end
	end
	return out
end

-- Same flattening for the comments endpoint: a comment always carries
-- `body`, a page never does.
local function flattenComments(raw: any): { any }
	local out: { any } = {}
	if type(raw) ~= "table" then
		return out
	end
	for _, entry in raw do
		if type(entry) == "table" and entry.body == nil then
			for _, item in entry do
				table.insert(out, item)
			end
		else
			table.insert(out, entry)
		end
	end
	return out
end

local function mapIssue(entry: any, queueLabel: string, login: string): Candidate
	local hasQueueLabel = false
	local labels = entry.labels
	if type(labels) == "table" then
		for _, label in labels do
			if type(label) == "table" and label.name == queueLabel then
				hasQueueLabel = true
			end
		end
	end
	-- Foreign-assigned: the issue has assignees and none of them is the
	-- authenticated account. No assignees is not foreign, and a teammate
	-- cc'd alongside the account is not foreign (ADR 0003's among-not-sole
	-- rule). This client-side check is the only assignment signal.
	local assignedElsewhere = false
	local assignees = entry.assignees
	if type(assignees) == "table" then
		local any = false
		local mine = false
		for _, assignee in assignees do
			if type(assignee) == "table" then
				any = true
				if assignee.login == login then
					mine = true
				end
			end
		end
		assignedElsewhere = any and not mine
	end
	return {
		number = entry.number,
		url = if type(entry.html_url) == "string" then entry.html_url else "",
		title = if type(entry.title) == "string" then entry.title else "",
		body = if type(entry.body) == "string" then entry.body else "",
		hasQueueLabel = hasQueueLabel,
		assignedElsewhere = assignedElsewhere,
	}
end

-- The whole labeled queue, oldest first by issue number. `{owner}`/`{repo}`
-- resolve from the invocation directory (or `GH_REPO`), exactly like bare
-- `gh`, so config carries no repo field. No server-side assignee narrowing:
-- the issues endpoint takes a single `assignee` term and cannot express
-- "none or mine" as a union, so the client-side foreign-assignment check
-- decides over the full labeled queue. `--method GET` is explicit: `gh api`
-- defaults to POST as soon as a `-f` field is present.
local function listCandidates(queueLabel: string, login: string): { Candidate }
	local outcome = gh.run({
		"api",
		"--method",
		"GET",
		"--paginate",
		"--slurp",
		"/repos/{owner}/{repo}/issues",
		"-f",
		"state=open",
		"-f",
		"sort=created",
		"-f",
		"direction=asc",
		"-f",
		`labels={queueLabel}`,
	}, { json = true })
	if not outcome.ok then
		error(`{ERROR_PREFIX}: could not list issues carrying the queue label "{queueLabel}": {outcome.stderr}`)
	end
	local candidates: { Candidate } = {}
	for _, entry in flattenPages(outcome.json) do
		if type(entry) == "table" and entry.number ~= nil and entry.pull_request == nil then
			table.insert(candidates, mapIssue(entry, queueLabel, login))
		end
	end
	-- `created` ascending is `number` ascending, so the global oldest issue
	-- is always in the result; the defensive client-side sort keeps "oldest
	-- first" exact and stable regardless of the response's order.
	table.sort(candidates, function(a: Candidate, b: Candidate): boolean
		return a.number < b.number
	end)
	return candidates
end

-- One issue by number, for explicit-number mode.
local function fetchCandidate(number: number, queueLabel: string, login: string): Candidate
	local path = string.format("/repos/{owner}/{repo}/issues/%d", number)
	local outcome = gh.run({ "api", "--method", "GET", path }, { json = true })
	if not outcome.ok then
		error(`{ERROR_PREFIX}: could not read issue #{number}: {outcome.stderr}`)
	end
	local entry = outcome.json
	if type(entry) ~= "table" or entry.number == nil then
		error(`{ERROR_PREFIX}: issue #{number} was not found`)
	end
	if entry.pull_request ~= nil then
		error(`{ERROR_PREFIX}: #{number} is a pull request, not an issue`)
	end
	return mapIssue(entry, queueLabel, login)
end

-- Read all of one issue's comments, flattened. Comments are read from the
-- REST endpoint so the numeric `id` (monotonically increasing) is the order
-- tie-break; the GraphQL node id is not orderable.
local function listComments(number: number): { any }
	local outcome = gh.run({
		"api",
		"--method",
		"GET",
		"--paginate",
		"--slurp",
		string.format("/repos/{owner}/{repo}/issues/%d/comments", number),
	}, { json = true })
	if not outcome.ok then
		error(`{ERROR_PREFIX}: could not read comments on #{number}: {outcome.stderr}`)
	end
	return flattenComments(outcome.json)
end

local function isClaimComment(comment: any): boolean
	local body = comment.body
	return type(body) == "string" and string.find(body, MARKER, 1, true) ~= nil
end

local function hasClaimMarker(comments: { any }): boolean
	for _, comment in comments do
		if type(comment) == "table" and isClaimComment(comment) then
			return true
		end
	end
	return false
end

-- Post the claim comment. The response carries the numeric REST id and the
-- platform creation timestamp used for the read-back.
local function postClaim(number: number): { id: number, createdAt: string }
	local outcome = gh.run({
		"api",
		"--method",
		"POST",
		string.format("/repos/{owner}/{repo}/issues/%d/comments", number),
		"-f",
		`body={CLAIM_BODY}`,
	}, { json = true })
	if not outcome.ok then
		error(`{ERROR_PREFIX}: could not post the claim on #{number}: {outcome.stderr}`)
	end
	local id = outcome.json.id
	if type(id) ~= "number" then
		error(`{ERROR_PREFIX}: the claim on #{number} carried no numeric comment id`)
	end
	local createdAt = outcome.json.created_at
	return { id = id, createdAt = if type(createdAt) == "string" then createdAt else "" }
end

-- Add the optional claimed label without touching the queue label. The
-- labels endpoint adds; it never replaces the issue's labels.
local function addClaimedLabel(number: number, label: string)
	local outcome = gh.run({
		"api",
		"--method",
		"POST",
		string.format("/repos/{owner}/{repo}/issues/%d/labels", number),
		"-f",
		`labels[]={label}`,
	})
	if not outcome.ok then
		error(`{ERROR_PREFIX}: could not add the claimed label "{label}" to #{number}: {outcome.stderr}`)
	end
end

-- Add the winning run's own account to the issue's assignees, after the
-- read-back confirmed the win. The assignees endpoint adds; it never removes
-- or replaces any assignee.
local function addSelfAssignee(number: number, login: string)
	local outcome = gh.run({
		"api",
		"--method",
		"POST",
		string.format("/repos/{owner}/{repo}/issues/%d/assignees", number),
		"-f",
		`assignees[]={login}`,
	})
	if not outcome.ok then
		error(`{ERROR_PREFIX}: could not add the authenticated account "{login}" as an assignee of #{number}: {outcome.stderr}`)
	end
end

-- Order two claim comments: earliest platform creation timestamp first, the
-- lowest numeric id as tie-break (same-second claims). An empty timestamp
-- sorts last, so a malformed one never wins on order alone.
local function claimBefore(a: { id: number, createdAt: string }, b: { id: number, createdAt: string }): boolean
	if a.createdAt == "" or b.createdAt == "" then
		if a.createdAt ~= b.createdAt then
			return b.createdAt == ""
		end
		return a.id < b.id
	end
	if a.createdAt ~= b.createdAt then
		return a.createdAt < b.createdAt
	end
	return a.id < b.id
end

local function earliestClaim(comments: { any }): { id: number, createdAt: string }?
	local best: { id: number, createdAt: string }? = nil
	for _, comment in comments do
		if type(comment) == "table" and isClaimComment(comment) and type(comment.id) == "number" then
			local candidate = {
				id = comment.id,
				createdAt = if type(comment.created_at) == "string" then comment.created_at else "",
			}
			if best == nil or claimBefore(candidate, best) then
				best = candidate
			end
		end
	end
	return best
end

-- One claim attempt: queue label → foreign-assignment → claim marker, then
-- post → read-back → winners-only writes. Only the marker signal needs a
-- comments read. Nothing but the marker is written before the read-back
-- confirms the win; a winner then self-assigns and, when configured, adds
-- `claimedLabel`. Every attempt reads comments at most twice (pre-check +
-- read-back); contention correctness never depends on the label.
local function attempt(candidate: Candidate, login: string, claimedLabel: string?): Attempt
	if not candidate.hasQueueLabel then
		return { status = "ineligible", reason = "label" }
	end
	if candidate.assignedElsewhere then
		return { status = "ineligible", reason = "assigned-elsewhere" }
	end

	local precheck = listComments(candidate.number)
	if hasClaimMarker(precheck) then
		return { status = "ineligible", reason = "claimed" }
	end

	local posted = postClaim(candidate.number)

	local readBack = listComments(candidate.number)
	local winner = earliestClaim(readBack)
	if winner == nil then
		error(`{ERROR_PREFIX}: the claim on #{candidate.number} was not found after posting`)
	end
	if winner.id ~= posted.id then
		-- Lost the race: write nothing further (the losing marker stays as
		-- accepted audit noise) and let the caller move on.
		return { status = "lost" }
	end

	-- Won: only now record the win on the issue. A cosmetic write failing
	-- here raises with the transport's stderr; the claim marker remains on
	-- the issue as the source of truth.
	addSelfAssignee(candidate.number, login)
	if claimedLabel ~= nil then
		addClaimedLabel(candidate.number, claimedLabel)
	end

	return {
		status = "claimed",
		brief = {
			number = candidate.number,
			url = candidate.url,
			title = candidate.title,
			body = candidate.body,
			claimCommentId = posted.id,
		},
	}
end

local M = {}

function M.new(config: Config): Instance
	local queueLabel = config.queueLabel
	local claimedLabel = config.claimedLabel

	-- The authenticated login is resolved at most once per instance, so a
	-- multi-candidate scan (and every later pickUp) resolves once.
	local cachedLogin: string? = nil
	local function login(): string
		if cachedLogin == nil then
			cachedLogin = resolveLogin()
		end
		return cachedLogin :: string
	end

	local instance: Instance = {
		pickUp = function(_self: Instance, number: number?): Outcome
			local me = login()
			if number ~= nil then
				local candidate = fetchCandidate(number, queueLabel, me)
				local result = attempt(candidate, me, claimedLabel)
				if result.status == "claimed" then
					return result
				end
				if result.status == "ineligible" then
					if result.reason == "label" then
						error(`{ERROR_PREFIX}: #{number} does not carry the queue label "{queueLabel}"`)
					end
					if result.reason == "assigned-elsewhere" then
						error(`{ERROR_PREFIX}: #{number} is assigned to another account`)
					end
					error(`{ERROR_PREFIX}: #{number} is already claimed`)
				end
				error(`{ERROR_PREFIX}: lost the claim on #{number} to an earlier runner`)
			end

			local candidates = listCandidates(queueLabel, me)
			-- The scan summary counts issues examined under the full scope:
			-- labeled and not assigned to another account.
			local scanned = 0
			for _, candidate in candidates do
				if candidate.hasQueueLabel and not candidate.assignedElsewhere then
					scanned += 1
				end
			end
			for _, candidate in candidates do
				local result = attempt(candidate, me, claimedLabel)
				if result.status == "claimed" then
					return result
				end
				-- Ineligible (label, assigned-elsewhere, or claimed) or lost:
				-- back off to the next candidate.
			end
			return { status = "no-eligible-issue", scanned = scanned }
		end,
	}
	return instance
end

return M
