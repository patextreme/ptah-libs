## MODIFIED Requirements

### Requirement: openspec playbook

The library SHALL provide an openspec playbook whose instance exposes
groom, implement, and verify operations on a named change: groom converges a
change's proposals through review, implement drives task execution, and
verify converges verification then syncs and archives the change. The
playbook SHALL declare its environment requirements (an agent carrying the
openspec skills, `openspec` on PATH) in its documentation rather than
bundling or installing them. Convergence is the playbook's own loop over
the library's typed judge: a judge-rejected pass probes the work session,
and the probe's claim is judged by a typed predicate. An ask is justified
only by an operator-owned decision — one the agent has no authority to
take and the loop cannot reverse at bounded cost; product direction,
architecture, and scope are examples in the prompt copy, not gates. A
confirmed operator-owned decision escalates through the library's
escalation mechanism — a served ask resumes the loop with the human's
answer, and an unservable or refused ask fails the operation without
issuing a fix. A confirmation, an approval to proceed, or a recoverable
choice (a decision whose wrong outcome the judge's next rejection
repairs) never escalates: the claim fails the predicate and the loop
issues the fix prompt. Exhausting the iteration cap fails the operation
with an error reporting the cap.

Every work prompt SHALL carry a component-owned autonomy clause
instructing the agent to make judgment calls autonomously, note each in
the pass output, and never wait for confirmation; the clause SHALL NOT be
configurable away. The noted judgment calls ride the pass output, so the
operation's returned text carries every autonomous decision the agent
took.

On a confirmed operator-owned decision, the playbook SHALL ask through the
library's escalation mechanism with an ask whose prompt line identifies
the operation, the change, and the iteration state, and whose details
carry the work session's label and the full probe text. When the ask is
answered, the answer text SHALL be sent verbatim as the next prompt of
the still-open work session (no header or framing added), the iteration
SHALL count against the cap, and the loop SHALL continue toward
convergence. When the human aborts the ask, the operation SHALL fail with
a distinct error stating the human aborted the escalation. When no ask
provider serves the request, the operation SHALL fail with an error
stating human input is needed — the same wording as before the ask
existed.

The playbook's config SHALL accept `sessionConfig`, an ordered
session-config entry array applied to every work session the playbook
creates — every per-iteration session of groom, implement, and verify, and
verify's archive session — and `judgeSessionConfig`, applied to every judge
and human-escalation-probe session. The `model` and `judgeModel` config
fields SHALL NOT exist: a model choice is an ordinary `sessionConfig`
entry, and the entry order is the consumer's `setConfig` order.

implement SHALL accept an optional task scope: free text describing the
subset of the change's tasks the run is responsible for. When a scope is
given, the work prompt SHALL instruct the agent to treat the scoped tasks
as the entire job and leave all other tasks pending, and the loop's
acceptance SHALL be judged against the scope rather than against the
whole change. The scope SHALL be carried to the judge so the verdict is
made against the scoped completion, without the judge needing the work
prompt. A scope that matches no tasks SHALL end the pass with a stated
dead-end rather than the agent substituting a different subset, and the
escalation path SHALL surface it (an ask when a provider serves it; an
operation error otherwise).
groom and verify SHALL remain whole-change operations.

#### Scenario: Verify converges and archives

- **WHEN** verify runs on a change whose implementation passes the verification judge
- **THEN** the verification loop exits and the sync-and-archive step runs as part of the same operation

#### Scenario: Missing environment requirement

- **WHEN** the playbook's documentation is consulted for its environment requirements
- **THEN** the agent-skill and CLI requirements are listed so a consumer can verify them before running

#### Scenario: Human escalation

- **WHEN** a groom pass is judge-rejected and the escalation judge confirms the pass cannot proceed without an operator-owned decision
- **THEN** the need escalates through the library's escalation mechanism — an answered ask resumes the loop with the human's answer; an aborted or unservable ask fails the operation with an error stating human input is needed, and no fix prompt is issued

#### Scenario: Confirmation-seeking never escalates

- **WHEN** a judge-rejected pass's probe asks for confirmation, approval to proceed, or a choice among reasonable alternatives, and the escalation judge finds no operator-owned decision in the probe
- **THEN** no ask is raised; the predicate returns false, the loop issues the fix prompt, and the agent decides autonomously, noting the judgment call in its pass output

#### Scenario: Work prompts carry the autonomy clause

- **WHEN** any operation composes a work prompt
- **THEN** the component-owned autonomy clause is appended — instructing the agent to make judgment calls autonomously, note each in the pass output, and never wait for confirmation — and the noted judgment calls ride the operation's returned text

#### Scenario: Human escalation asks and resumes

- **WHEN** a groom pass is judge-rejected, the escalation judge confirms an operator-owned decision is required, an ask provider serves the request, and the human answers
- **THEN** the answer is sent verbatim as the next prompt of the still-open work session, the iteration counts against the cap, and the loop continues toward convergence

#### Scenario: Human escalation abort fails

- **WHEN** a groom pass is judge-rejected, the escalation judge confirms an operator-owned decision is required, an ask provider serves the request, and the human aborts the ask
- **THEN** the operation fails with a distinct error stating the human aborted the escalation, and no fix prompt is issued

#### Scenario: Unservable ask fails as before

- **WHEN** a groom pass is judge-rejected, the escalation judge confirms an operator-owned decision is required, and no ask provider serves the request
- **THEN** the operation fails with an error stating human input is needed — the same wording as before the ask existed — and no fix prompt is issued

#### Scenario: Ask carries identity, session label, ACP session id, and full probe text

- **WHEN** the playbook raises an escalation ask
- **THEN** the prompt line identifies the operation, the change, and the iteration state, and the details carry the work session's label, the agent-side ACP session id, and the full probe text without truncation

#### Scenario: Iteration cap

- **WHEN** every pass is judge-rejected and the findings stay fixable up to the configured iteration cap
- **THEN** the operation fails with an error reporting the cap was reached

#### Scenario: Scoped implement completes the subset

- **WHEN** implement runs with a task scope and the agent implements the tasks matching that scope
- **THEN** the judge accepts the pass and the operation exits successfully while tasks outside the scope remain pending

#### Scenario: Scopeless implement is unchanged

- **WHEN** implement runs without a task scope
- **THEN** the prompts, judge acceptance, and log lines are identical to the behavior before task scopes existed, with completion judged against all tasks of the change

#### Scenario: Unresolvable scope dead-ends

- **WHEN** implement runs with a task scope that matches no tasks of the change
- **THEN** the agent ends the pass stating that the scope matches no tasks without implementing a substitute subset, and the dead-end surfaces through the escalation path (an ask when a provider serves it; the operation fails otherwise)

#### Scenario: Work sessions receive session config

- **WHEN** the playbook is configured with `sessionConfig` entries and any operation runs
- **THEN** every per-iteration work session, and verify's archive session, receives the entries in declared order before its first prompt

#### Scenario: Judge and probe sessions receive judge session config

- **WHEN** the playbook is configured with `judgeSessionConfig` entries and any operation runs
- **THEN** every judge session and every human-escalation-probe session receives the entries in declared order before its prompt

#### Scenario: Removed model field is a type error

- **WHEN** a consumer shim configures the removed `model` or `judgeModel` field and runs `ptah check`
- **THEN** check reports a type error naming the unknown field, steering the consumer to the `sessionConfig` entry form

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
review prose, the ledger state (open and deferred findings with their ids), the PR's
intention, and the configured `blockingAdditions` text, and SHALL return typed findings
carrying per-finding severity (blocking or non-blocking), a family name, a validation
status, and the judge's `needsHuman` determination, together with a reconciliation of
the ledger's findings — resolved (with evidence), still open, or still deferred —
covering both open and deferred entries. The judge SHALL steer findings against the
PR's intention: a finding the judge rates important but outside the PR's scope SHALL
be recorded with a deferred status in the ledger, SHALL NOT gate convergence, and
SHALL be surfaced in the PR review report's deferred list. A recurrence of a deferred
finding SHALL be reported against that finding's id as still deferred, never refiled
as a new finding. A judge that submits no typed result SHALL be retried a bounded
number of times, and exhaustion SHALL fail the iteration — never a silent converge.
The judge agent is a required config handle: the loop's convergence depends on it,
and no prose-parsing fallback replaces it.

Convergence SHALL be computed from the judge's typed output: the loop converges when
no open blocking findings remain. The loop's budget is a single
`maxIterations` cap (default 8) over review passes. A fix turn SHALL be issued only
when open blocking findings exist and budget remains; when the cap is reached with
open findings, the loop SHALL NOT fix — it SHALL end and report a non-converged
outcome. Every pushed fix is therefore followed by at least one review pass. A fix
turn SHALL address all open blocking findings in one turn, by root cause, and SHALL
commit and push (gated by dry-run).

The work session SHALL NOT post to the pull request. For every terminal outcome that
returns (converged or non-converged), the playbook SHALL produce a PR review report
per the PR review report requirement.

The loop SHALL NOT ask a human at any point: the pull request itself, reviewed by
its human at merge time, is the loop's human checkpoint. The judge's `needsHuman`
flag is report-only: the judge SHALL set it only on an open blocking finding that
rests on an operator-owned decision — one the agent has no authority to take — that
a human should examine at review; the flag SHALL NOT be set on a deferred or
non-blocking finding. The flag persists in the ledger, renders on the finding's line
in the PR review report, and never gates, pauses, or fails the loop: an open
blocking finding carrying `needsHuman` is fixed autonomously like any other
blocking finding. A `needsHuman` determination on a non-blocking or deferred
finding, and a reconciliation record naming an id absent from the ledger, have no
loop effect: the determination persists and renders in the report. Legacy ledgers
carrying a decisions record or `accepted` findings SHALL be read tolerantly; no new
decisions are recorded.

The playbook's config SHALL accept `agent` and the required `judgeAgent` and
`reporterAgent` handles, `sessionConfig` (applied to every work session the playbook
creates), `judgeSessionConfig` (applied to every judge session),
`reporterSessionConfig` (applied to every reporter session),
`reviewInstruction` (persona, per the instruction contract), `blockingAdditions`
(free text supplied to the judge defining what counts as blocking for the
repository), `dryRun`, and `maxIterations` (default 8). The `model` and `judgeModel`
config fields SHALL NOT exist: a model choice is an ordinary `sessionConfig` entry,
and the entry order is the consumer's `setConfig` order.

The `review` operation SHALL return a typed outcome carrying a status
(`converged` / `non-converged`), the final verdict text, the final ledger snapshot,
and the posted report text (`report`) — outcomes as data, matching the library's
transport conventions — rather than a bare verdict string.

#### Scenario: First pass reviews the whole PR

- **WHEN** the loop reviews a PR with no existing ledger
- **THEN** the first review pass targets the entire PR and its result is recorded in a new ledger with the discovery SHA and the PR's intention

#### Scenario: Later passes review only the delta

- **WHEN** the loop runs a review pass after a fix has been pushed
- **THEN** the review prompt carries the ledger's `lastReviewedSha` and directs the reviewer to review only the changes since that commit and to report recurrences by ledger finding id, and the ledger's `lastReviewedSha` advances

#### Scenario: Judge converts prose to typed findings

- **WHEN** the work session completes a review in prose
- **THEN** a typed judge session receives the prose, the ledger's open and deferred findings with their ids, the PR intention, and the configured `blockingAdditions`, and returns structured findings (severity, family, validation status, `needsHuman`) plus a reconciliation of those findings (resolved with evidence, still open, or still deferred)

#### Scenario: Convergence is computed from typed findings

- **WHEN** the judge's typed output reports no open blocking findings
- **THEN** the loop converges and the playbook produces a PR review report whose status line reports convergence

#### Scenario: Review finds fixable findings

- **WHEN** the judge's typed output reports open blocking findings and budget remains
- **THEN** the work session is prompted to resolve all of them in one fix turn addressing the root cause — including any carrying `needsHuman` — followed by commit-and-push (gated by dry-run), iterating until the review converges or the cap ends the loop

#### Scenario: needsHuman is report-only

- **WHEN** the judge flags `needsHuman` on an open blocking finding
- **THEN** the loop issues the fix turn for it like any other blocking finding, no ask is raised, the flag persists in the ledger, and the PR review report renders it on the finding's line for the reviewing human

#### Scenario: Resume auto-fixes flagged findings

- **WHEN** a fresh `review` operation resumes a ledger holding an open blocking finding carrying `needsHuman`
- **THEN** the resume fast path issues the fix turn for it like any other open blocking finding, without an ask — the flag is the reviewer's pointer, not a gate

#### Scenario: Non-blocking needsHuman does not ask

- **WHEN** the judge flags `needsHuman` on a non-blocking or deferred finding and open blocking findings exist
- **THEN** no ask exists to raise — the loop issues the batched fix turn for the open blocking findings, and the flagged concern's `needsHuman` determination is persisted in the ledger and rendered in the PR review report

#### Scenario: Unknown reconciliation id never escalates

- **WHEN** a reconciliation record flags `needsHuman` naming an id that matches no ledger finding
- **THEN** the record has no loop effect — no ask exists to trigger — and the loop proceeds by its convergence state alone

#### Scenario: Answer is adjudicated before any fix turn

- **WHEN** a review pass reports open blocking findings (the moment that previously raised an ask)
- **THEN** no adjudication occurs — no ask is raised and no answer path exists; the loop proceeds directly by its convergence state (fix turn, or converge)

#### Scenario: Human decision reaches the ledger

- **WHEN** a human reviews the PR after a loop run
- **THEN** human decisions land at PR review time — the merge review, guided by the report's `needsHuman` flags — never in the ledger mid-run; legacy decisions records are read tolerantly and no new ones are written

#### Scenario: Human escalation asks and resumes

- **WHEN** the judge flags `needsHuman` on an open blocking finding
- **THEN** the loop asks nothing — the flagged finding drives the fix turn autonomously like any other blocking finding, and the next review pass re-judges the fix

#### Scenario: Decision-only adjudication converges immediately

- **WHEN** a review pass leaves no open blocking findings
- **THEN** the loop converges — convergence is computed solely from open blocking findings; no decision path exists to converge it earlier

#### Scenario: Adjudication mutations are inert on unknown or terminal ids

- **WHEN** the loop processes a judge pass
- **THEN** no mutations exist — the ledger's only writers are filing (open or deferred), reconciliation (resolved or updated), and verification (fixed); no mid-run path writes finding status by human decision

#### Scenario: Duplicate adjudication ids keep the last decision

- **WHEN** a judge pass reports findings
- **THEN** no per-finding human decision exists to duplicate or order — ids are assigned at filing and never mutated by a decision

#### Scenario: Adjudication exhaustion fails the iteration

- **WHEN** a typed session submits no result on every attempt up to the bound
- **THEN** the judge session's bounded retry and exhaustion behavior is the only typed-result retry in the loop — the adjudication session no longer exists

#### Scenario: Ask carries identity, session label, ACP session id, and full probe text

- **WHEN** the loop runs to a terminal outcome
- **THEN** no ask is raised, so no ask payload exists; the report comment is the only human-facing channel, and it carries the ledger, the flags, and the prose

#### Scenario: Human escalation abort fails

- **WHEN** a run reaches the moment that previously raised an ask a human could abort
- **THEN** no ask exists to abort — the operation never fails on human refusal; a human who disagrees with a run's direction lets it finish (or kills it) and rules at PR review time

#### Scenario: Unservable ask fails as before

- **WHEN** the loop runs in an environment with no ask provider
- **THEN** ask-provider availability is irrelevant — no ask is raised, so a provider-less environment behaves identically to a served one

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

#### Scenario: Deferred recurrence reconciles by id

- **WHEN** a later review pass flags a concern matching a deferred ledger finding
- **THEN** the judge's reconciliation reports it against the existing finding's id as still deferred, and the ledger records no duplicate entry for the same concern

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

- **WHEN** the `review` operation ends — converged, or non-converged at the cap
- **THEN** the operation returns a typed outcome carrying the status (`converged` / `non-converged`), the final verdict text, the final ledger snapshot, and the report text, rather than only a verdict string

### Requirement: PR review ledger

The pr-review-loop playbook SHALL persist its loop state as a ledger stored in a
dedicated pull-request comment (marked `<!-- ptah:pr-review-ledger -->` and updated in
place through the library's GitHub transport), not in playbook config or local state.
The ledger SHALL carry: the PR identity, the discovery SHA and the `lastReviewedSha`,
the PR's intention (the PR title and body when present; otherwise the last commit
message before the first ledger record, captured at discovery), the findings with
their id, family, severity, validation status, the judge's `needsHuman` determination,
status (`open` / `fixed` / `deferred` / `accepted`), and fixing commit where
applicable, and the family table. The ledger SHALL be playbook-owned data; the
documentation SHALL state that hand-editing it is unsupported, that a deleted ledger
degrades a fresh run to a new discovery pass (today's per-run behavior), and that one
loop per PR is an environment requirement (two concurrent loops on one PR corrupt
the in-place comment update). Legacy ledgers carrying a decisions record SHALL be
read tolerantly; no new decisions are recorded.

A finding's `needsHuman` flag SHALL be recorded when the finding is filed, SHALL be
updated whenever a later reconciliation revisits the finding (the judge's latest
determination wins), and never clears — there is no mid-loop human decision to
supersede it. A ledger written before the flag existed SHALL be read tolerantly: a
finding without the field is treated as not needing a human, and the field is
written on the next persist.

Finding status SHALL be written by the judge at filing (open, or deferred for
out-of-scope concerns) and by the reconciliation path (open → fixed when a fix is
verified clean). Deferred is terminal: it has no exit transitions, and a deferred
concern that becomes in-scope again is filed as a new open finding. `accepted` is a
legacy status: read tolerantly, terminal, and no new transition writes it (its only
writer was the retired adjudication path).

A fresh `review` operation SHALL resume automatically from an existing ledger without
a resume flag: no ledger means a fresh discovery pass; an existing ledger means the
loop continues from its state (open blocking findings — regardless of any
`needsHuman` flag — drive a fix turn; a clean ledger at the current head converges).

Once a finding's fix has been verified clean in a later review pass, the playbook
SHALL retain it as a terminal one-line entry with status `fixed` — its id, title,
family, and fixing commit — and increment the resolved count, rather than collapsing
it to a bare count, so the PR review report can list what was fixed. A `fixed` entry
no longer participates in reconciliation and never gates convergence. Retaining fixed
entries means the ledger grows with the PR; a ledger that outgrows the platform
comment limit fails loudly through the transport rather than truncating.

#### Scenario: Ledger created at discovery

- **WHEN** the loop's first review pass completes on a PR with no ledger comment
- **THEN** a ledger comment is created carrying the discovery SHA, the last reviewed SHA, the PR's intention, and the typed findings with their families, validation statuses, and `needsHuman` determinations

#### Scenario: needsHuman flag persists, updates, and clears

- **WHEN** a finding is filed with `needsHuman` flagged and a later reconciliation revisits the finding
- **THEN** the ledger carries the judge's latest determination and the flag never clears — no mid-loop human decision exists to supersede it — and the PR review report renders it on the finding's line

#### Scenario: Decisions recorded on answered asks

- **WHEN** the loop reads a ledger carrying a decisions record from before the ask was retired
- **THEN** no new decisions are recorded — the decisions record is never written; legacy entries are read tolerantly and dropped on the next persist

#### Scenario: Legacy ledgers read tolerantly

- **WHEN** the loop reads a ledger written before the `needsHuman` field existed, or one carrying a decisions record or `accepted` findings from before the ask was retired
- **THEN** findings parse without the field and are treated as not needing a human, decisions are ignored, `accepted` findings stay terminal, and the flag field is written on the next persist

#### Scenario: Fresh run resumes from the ledger

- **WHEN** a new `review` operation runs against a PR whose ledger comment exists (e.g. after a previous run ended at the cap)
- **THEN** the loop resumes from the ledger's state without a resume flag — open blocking findings (flagged or not) drive a fix turn, a clean ledger at the current head converges immediately

#### Scenario: Ledger updated in place after each phase

- **WHEN** a review pass or fix turn completes
- **THEN** the ledger comment is updated in place (never appended as a new comment) reflecting the new `lastReviewedSha`, finding statuses, `needsHuman` flags, and family table

#### Scenario: Intention fallback

- **WHEN** the PR has no body at discovery time
- **THEN** the ledger's intention is captured from the last commit message before the first ledger record, and later passes reuse the cached intention

#### Scenario: Resolved findings compact

- **WHEN** a finding's fix has been verified clean in a later review pass
- **THEN** the ledger retains the finding as a terminal one-line entry with status `fixed` (id, title, family, fixing commit) rather than dropping it to a bare count, increments the resolved count, and no longer treats it as open — so the PR review report can list what was fixed

#### Scenario: One loop per PR is a documented requirement

- **WHEN** a consumer consults the playbook's documentation for environment requirements
- **THEN** the one-loop-per-PR requirement is stated alongside the `gh`-based PR-host requirement, and the documentation states the consequence of violating it (concurrent in-place ledger updates corrupting each other)

### Requirement: PR review report

The pr-review-loop playbook SHALL produce a **PR review report** — a human-facing
summary of the whole review — as a pull-request comment marked
`<!-- ptah:pr-review-report -->` and edited in place across runs, for every terminal
outcome of a `review` operation that returns (converged and non-converged). A `review`
operation that fails — reporter exhaustion — SHALL NOT produce a report.

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
entries; the open non-blocking findings; the deferred findings; the accepted findings
(legacy ledgers only — no new run produces them); and a loop summary (iterations,
discovery and last-reviewed SHAs, and the family table). For a non-converged outcome
the report SHALL lead with an open blocking findings section beneath the status line.
The resolved findings list SHALL be capped at 50 entries with a note of how many
earlier entries are omitted, so the report stays readable while the ledger retains
every entry.

The reporter session SHALL receive the full ledger, the terminal status, and the
required section contract, so the report reflects the whole loop rather than the last
delta alone. It SHALL additionally receive the last review pass's prose when a review
pass ran in the current operation; a resume that converges immediately, or that ends
at the cap without a new review pass, has none, and the report is rendered from the
ledger alone. The ledger is the durable whole-loop source; the prose is supplementary.

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

- **WHEN** the playbook prompts the reporter after a review pass ran in the current operation
- **THEN** the prompt carries the full ledger (including retained `fixed` entries), the terminal status, the last review pass's prose, and the section contract

#### Scenario: Reporter runs without prose on a resume

- **WHEN** a `review` operation returns without running a new review pass — an immediate resume converge, or a resumed ledger already at the cap — and a report is produced
- **THEN** the reporter prompt carries the full ledger, the terminal status, and the section contract with an explicit no-prose marker instead of review prose, and the operation still returns `outcome.report`

#### Scenario: Reporter session config is applied

- **WHEN** the playbook is configured with `reporterSessionConfig` entries and a report is produced
- **THEN** the reporter session receives the entries in declared order before its prompt

#### Scenario: Resolved list is capped

- **WHEN** the ledger holds more than 50 retained `fixed` entries
- **THEN** the report's resolved section lists 50 and notes how many earlier entries are omitted, while the ledger continues to retain every entry
