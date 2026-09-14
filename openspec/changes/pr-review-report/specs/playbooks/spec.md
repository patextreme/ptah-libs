## MODIFIED Requirements

### Requirement: PR review loop playbook

The library SHALL provide a PR review loop playbook that runs a convergent
review→validate→fix→verify loop against a pull request, with repository-specific
settings expressed as config rather than code. The target repository SHALL NOT be
playbook config: it arrives per call inside the PR URL. The playbook SHALL NOT read
CI results or execute repo-specific gate commands; deterministic signal ingestion and
post-loop policy are the calling script's responsibility. The playbook SHALL document
this boundary.

The loop's first review pass against a PR without an existing ledger is a full-PR
review (discovery). Every subsequent review pass SHALL be a delta review: the review
prompt carries the ledger's `lastReviewedSha` and directs the reviewer to review only
the changes since that commit and report recurrences by ledger finding id rather than
refiling them.

The work session reviews freely in prose following its persona instruction and SHALL
validate blocking findings with its own in-session subagents before finalizing its
review. The directive to do so SHALL be carried by the component-owned protocol
fragment, not the configurable persona, so a persona replacement cannot remove it.
The playbook SHALL convert the work session's prose into structured data
through a typed judge session (a `resultSchema` result): the judge SHALL receive the
review prose, the ledger state, the PR's intention, and the configured
`blockingAdditions` text, and SHALL return typed findings carrying per-finding
severity (blocking or non-blocking), a family name, a validation status, and the
judge's `needsHuman` determination, together with a reconciliation of the ledger's
open findings (resolved, with evidence, or still open). The judge SHALL steer
findings against the PR's intention: a finding the judge rates important but outside
the PR's scope SHALL be recorded with a deferred status in the ledger, SHALL NOT gate
convergence, and SHALL be surfaced in the PR review report's deferred list. A judge
that submits no typed result SHALL be retried a bounded number of times, and
exhaustion SHALL fail the iteration — never a silent converge. The judge agent is a
required config handle: the loop's convergence depends on it, and no prose-parsing
fallback replaces it.

Convergence SHALL be computed from the judge's typed output: the loop converges when
no open blocking findings remain. The loop's budget is a single `maxIterations` cap
(default 8) over review passes. A fix turn SHALL be issued only when open blocking
findings exist and budget remains; when the cap is reached with open findings, the
loop SHALL NOT fix — it SHALL end and report a non-converged outcome. Every pushed fix
is therefore followed by at least one review pass. A fix turn SHALL address all open
blocking findings in one turn, by root cause, and SHALL commit and push (gated by
dry-run).

The work session SHALL NOT post to the pull request. For every terminal outcome that
returns (converged or non-converged), the playbook SHALL produce a PR review report
per the PR review report requirement.

The loop's only escalation trigger is the judge's `needsHuman` flag. When flagged,
the loop SHALL ask through the library's escalation mechanism with an ask whose prompt
line identifies the loop and the PR URL and the iteration state, and whose details
carry the work session's label and the full review prose. When the ask is answered,
the answer text SHALL be sent verbatim as the next prompt of the still-open work
session (no header or framing added), the commit-and-push step SHALL still follow the
human-guided fix (gated by dry-run as any fix), the iteration SHALL count against the
cap, and the loop SHALL continue toward convergence. When the human aborts the ask,
the operation SHALL fail with a distinct error stating the human aborted the
escalation. When no ask provider serves the request, the operation SHALL fail with an
error stating human input is needed to resolve the findings.

The playbook's config SHALL accept `agent` and the required `judgeAgent` and
`reporterAgent` handles, `sessionConfig` (applied to every work session the playbook
creates), `judgeSessionConfig` (applied to every judge session),
`reporterSessionConfig` (applied to every reporter session), `reviewInstruction`
(persona, per the instruction contract), `blockingAdditions` (free text supplied to
the judge defining what counts as blocking for the repository), `dryRun`, and
`maxIterations` (default 8). The `model` and `judgeModel` config fields SHALL NOT
exist: a model choice is an ordinary `sessionConfig` entry, and the entry order is
the consumer's `setConfig` order.

The `review` operation SHALL return a typed outcome carrying a status
(`converged` / `non-converged`), the final verdict text, the final ledger snapshot,
and the report text — outcomes as data, matching the library's transport conventions
— rather than a bare verdict string. Escalation failures do not appear in the
outcome: an aborted or unservable ask fails the operation with an error, and an
answered ask continues the loop toward convergence, so the returned status is always
`converged` or `non-converged`.

#### Scenario: First pass reviews the whole PR

- **WHEN** the loop reviews a PR with no existing ledger
- **THEN** the first review pass targets the entire PR and its result is recorded in a new ledger with the discovery SHA and the PR's intention

#### Scenario: Later passes review only the delta

- **WHEN** the loop runs a review pass after a fix has been pushed
- **THEN** the review prompt carries the ledger's `lastReviewedSha` and directs the reviewer to review only the changes since that commit and to report recurrences by ledger finding id, and the ledger's `lastReviewedSha` advances

#### Scenario: Judge converts prose to typed findings

- **WHEN** the work session completes a review in prose
- **THEN** a typed judge session receives the prose, the ledger, the PR intention, and the configured `blockingAdditions`, and returns structured findings (severity, family, validation status, `needsHuman`) plus a reconciliation of the ledger's open findings

#### Scenario: Convergence is computed from typed findings

- **WHEN** the judge's typed output reports no open blocking findings
- **THEN** the loop converges and the playbook produces a PR review report whose status line reports convergence

#### Scenario: Review finds fixable findings

- **WHEN** the judge's typed output reports open blocking findings and budget remains, and the judge does not flag `needsHuman`
- **THEN** the work session is prompted to resolve all of them in one fix turn addressing the root cause, followed by commit-and-push (gated by dry-run), iterating until the review converges or escalation occurs

#### Scenario: Fix never consumes the last unit

- **WHEN** the judge reports open blocking findings and the iteration cap has been reached
- **THEN** no fix turn is issued; the loop ends, the operation returns a non-converged outcome carrying the verdict text, the ledger snapshot, and the report text, and the playbook produces a non-converged PR review report

#### Scenario: Judge exhaustion fails the iteration

- **WHEN** the judge session submits no typed result on every attempt up to the bound
- **THEN** the iteration fails with a script error naming the judge and the attempt count, and no fix turn is issued

#### Scenario: Validation happens in the work session

- **WHEN** the reviewer reports blocking findings during a review pass
- **THEN** the review prompt carries the component-owned protocol fragment's in-session validation directive, the work session validates the findings with its own in-session subagents, and the validation outcomes reach the judge as part of the review prose

#### Scenario: Deferred findings do not gate convergence

- **WHEN** the judge defers a finding as important but outside the PR's intention
- **THEN** the finding is recorded with a deferred status, the loop may converge with it open, and the PR review report lists it under deferred findings

#### Scenario: Human escalation asks and resumes

- **WHEN** the judge flags `needsHuman`, an ask provider serves the request, and the human answers
- **THEN** the answer is sent verbatim as the next prompt of the still-open work session, the commit-and-push step follows the human-guided fix (gated by dry-run as any fix), the iteration counts against the cap, and the loop continues toward convergence

#### Scenario: Human escalation abort fails

- **WHEN** the judge flags `needsHuman`, an ask provider serves the request, and the human aborts the ask
- **THEN** the operation fails with a distinct error stating the human aborted the escalation, and no fix is issued

#### Scenario: Unservable ask fails as before

- **WHEN** the judge flags `needsHuman` and no ask provider serves the request
- **THEN** the operation fails with an error stating human input is needed to resolve the findings — the same wording as before the ask existed — and no fix is issued

#### Scenario: Ask carries identity, session label, ACP session id, and full probe text

- **WHEN** the loop raises an escalation ask
- **THEN** the prompt line identifies the loop, the PR URL, and the iteration state, and the details carry the work session's label, the agent-side ACP session id, and the full review prose (the probe payload in this design) without truncation

#### Scenario: Repository context is per-call

- **WHEN** the loop reviews a pull request
- **THEN** the repository context comes from the PR URL passed to the operation, and the playbook's config declares no repository field

#### Scenario: Config surface

- **WHEN** a consumer constructs the playbook
- **THEN** the config accepts `agent`, the required `judgeAgent` and `reporterAgent`, `sessionConfig`, `judgeSessionConfig`, `reporterSessionConfig`, `reviewInstruction`, `blockingAdditions`, `dryRun`, and `maxIterations` (default 8), and the removed `model`/`judgeModel` fields are nil-typed so configuring one is a check error

#### Scenario: Work sessions receive session config

- **WHEN** the playbook is configured with `sessionConfig` entries and the review loop runs
- **THEN** every per-iteration work session receives the entries in declared order before its first prompt

#### Scenario: Judge and probe sessions receive judge session config

- **WHEN** the playbook is configured with `judgeSessionConfig` entries and the review loop runs
- **THEN** every judge session receives the entries in declared order before its prompt

#### Scenario: Removed model field is a type error

- **WHEN** a consumer shim configures the removed `model` or `judgeModel` field and runs `ptah check`
- **THEN** check reports a type error naming the unknown field, steering the consumer to the `sessionConfig` entry form

#### Scenario: Operation returns a typed outcome

- **WHEN** the `review` operation ends — converged, or non-converged at the cap (including a run whose last unit followed an answered ask)
- **THEN** the operation returns a typed outcome carrying the status (`converged` / `non-converged`), the final verdict text, the final ledger snapshot, and the report text, rather than only a verdict string, and an escalation failure raises an error instead of returning an outcome

### Requirement: PR review ledger

The pr-review-loop playbook SHALL persist its loop state as a ledger stored in a
dedicated pull-request comment (marked `<!-- ptah:pr-review-ledger -->` and updated in
place through the library's GitHub transport), not in playbook config or local state.
The ledger SHALL carry: the PR identity, the discovery SHA and the `lastReviewedSha`,
the PR's intention (the PR title and body when present; otherwise the last commit
message before the first ledger record, captured at discovery), the findings with
their id, family, severity, validation status, status (`open` / `fixed` / `deferred`
/ `accepted`), and fixing commit where applicable, and the family table. The ledger
SHALL be playbook-owned data; the documentation SHALL state that hand-editing it is
unsupported, that a deleted ledger degrades a fresh run to a new discovery pass
(today's per-run behavior), and that one loop per PR is an environment requirement
(two concurrent loops on one PR corrupt the in-place comment update).

A fresh `review` operation SHALL resume automatically from an existing ledger without
a resume flag: no ledger means a fresh discovery pass; an existing ledger means the
loop continues from its state (open blocking findings → fix turn; a clean ledger at
the current head → converge).

Once a finding's fix has been verified clean in a later review pass, the playbook
SHALL retain it as a terminal one-line entry with status `fixed` — its id, title,
family, and fixing commit — and increment the resolved count, rather than collapsing
it to a bare count, so the PR review report can list what was fixed. A `fixed` entry
no longer participates in reconciliation and never gates convergence. Retaining fixed
entries means the ledger grows with the PR; a ledger that outgrows the platform
comment limit fails loudly through the transport rather than truncating.

#### Scenario: Ledger created at discovery

- **WHEN** the loop's first review pass completes on a PR with no ledger comment
- **THEN** a ledger comment is created carrying the discovery SHA, the last reviewed SHA, the PR's intention, and the typed findings with their families and validation statuses

#### Scenario: Fresh run resumes from the ledger

- **WHEN** a new `review` operation runs against a PR whose ledger comment exists (e.g. after a previous run ended at the cap)
- **THEN** the loop resumes from the ledger's state without a resume flag — open blocking findings drive a fix turn, a clean ledger at the current head converges immediately

#### Scenario: Ledger updated in place after each phase

- **WHEN** a review pass or fix turn completes
- **THEN** the ledger comment is updated in place (never appended as a new comment) reflecting the new `lastReviewedSha`, finding statuses, and family table

#### Scenario: Intention fallback

- **WHEN** the PR has no body at discovery time
- **THEN** the ledger's intention is captured from the last commit message before the first ledger record, and later passes reuse the cached intention

#### Scenario: Resolved findings compact

- **WHEN** a finding's fix has been verified clean in a later review pass
- **THEN** the ledger compacts the finding to a terminal one-line entry with status `fixed` (id, title, family, fixing commit) rather than dropping it to a bare count, increments the resolved count, and no longer treats it as open — so the PR review report can list what was fixed

#### Scenario: One loop per PR is a documented requirement

- **WHEN** a consumer consults the playbook's documentation for environment requirements
- **THEN** the one-loop-per-PR requirement is stated alongside the `gh`-based PR-host requirement, and the documentation states the consequence of violating it (concurrent in-place ledger updates corrupting each other)

## ADDED Requirements

### Requirement: PR review report

The pr-review-loop playbook SHALL produce a **PR review report** — a human-facing
summary of the whole review — as a pull-request comment marked
`<!-- ptah:pr-review-report -->` and edited in place across runs, for every terminal
outcome of a `review` operation that returns (converged and non-converged). A `review`
operation that fails — an aborted or unservable escalation, or reporter exhaustion —
SHALL NOT produce a report.

The report SHALL be authored by a dedicated reporter agent: a required
`reporterAgent` config handle and an optional `reporterSessionConfig` (applied to
every reporter session in declared order). The reporter SHALL submit a typed result (a
`resultSchema` result) carrying the report body. The playbook SHALL retry a reporter
that submits no typed result a bounded number of times, and exhaustion SHALL fail the
operation with an error naming the reporter and the attempt count — never a silent
absence of the report. The converged work session SHALL NOT author or post the report.

The playbook SHALL post and edit the report through the library's GitHub transport,
matching the ledger's marker-and-edit pattern, so a re-run edits the existing report
rather than appending another. The playbook SHALL prepend a deterministic status line
derived from the ledger — the outcome status and the count of open blocking findings —
so the report's convergence claim is never agent-authored. The reporter SHALL author
the remainder of the body under a playbook-defined section contract.

The report body SHALL cover: the PR's intention; the resolved findings as one-line
entries; the open non-blocking findings; the deferred findings; the accepted findings;
and a loop summary (iterations, discovery and last-reviewed SHAs, and the family
table). For a non-converged outcome the report SHALL lead with an open blocking
findings section beneath the status line. The resolved findings list SHALL be capped
at a documented maximum with a note of how many earlier entries are omitted, so the
report stays readable while the ledger retains every entry.

The reporter session SHALL receive the full ledger, the terminal status, the last
review pass's prose, and the required section contract, so the report reflects the
whole loop rather than the last delta alone.

#### Scenario: Report produced on convergence

- **WHEN** a review pass converges and the review operation returns
- **THEN** the playbook posts a PR review report whose status line reports convergence and whose body covers the ledger's resolved, open non-blocking, deferred, and accepted findings and the loop summary

#### Scenario: Report produced on cap and leads with blockers

- **WHEN** the loop reaches the cap with open blocking findings and returns a non-converged outcome
- **THEN** the playbook posts a PR review report whose status line reports non-convergence and the open blocking count, and whose body leads with an open blocking findings section

#### Scenario: Report is edited in place across runs

- **WHEN** a `review` operation runs against a PR that already has a report comment
- **THEN** the playbook edits that comment in place rather than appending a second report

#### Scenario: Playbook owns the status line

- **WHEN** the report is produced for any outcome
- **THEN** the status line naming the outcome status and the open blocking count is composed by the playbook from the ledger, not by the reporter

#### Scenario: Reporter exhaustion fails the operation

- **WHEN** the reporter session submits no typed result on every attempt up to the bound
- **THEN** the review operation fails with a script error naming the reporter and the attempt count, and no report is posted

#### Scenario: Reporter receives the full ledger and the last review prose

- **WHEN** the playbook prompts the reporter
- **THEN** the prompt carries the full ledger (including retained `fixed` entries), the terminal status, the last review pass's prose, and the section contract

#### Scenario: Reporter session config is applied

- **WHEN** the playbook is configured with `reporterSessionConfig` entries and a report is produced
- **THEN** the reporter session receives the entries in declared order before its prompt

#### Scenario: Resolved list is capped

- **WHEN** the ledger holds more retained `fixed` entries than the report's documented maximum
- **THEN** the report's resolved section lists the maximum and notes how many earlier entries are omitted, while the ledger continues to retain every entry
