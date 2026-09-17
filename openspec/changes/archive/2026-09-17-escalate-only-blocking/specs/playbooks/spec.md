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

The loop's only escalation trigger is the judge's `needsHuman` flag on a finding that
gates convergence: the loop SHALL ask only when an open, blocking finding carries
`needsHuman`, whether raised as a new finding or through a reconciliation record. A
reconciliation record SHALL trigger the ask only when the ledger finding it names by
id is itself open and blocking; a record naming an id absent from the ledger SHALL
never trigger an ask. The `needsHuman` flag on a non-blocking or deferred finding
SHALL NOT trigger an ask: the concern surfaces in the review prose and the posted
report, with the flag persisted in the ledger.

When the trigger fires, the loop SHALL ask through the library's escalation mechanism
with an ask whose prompt line identifies the loop, the PR URL, and the iteration
state, and names every triggering finding (id, family, severity, title); the details
SHALL carry the answer grammar the loop understands (`defer <id>`,
`accept <id>`, `fix: <instructions>`), the work session's label, the agent-side ACP
session id, and the full review prose without truncation.

When the ask is answered, the answer SHALL be adjudicated before any fix turn: a
typed adjudication session — the judge agent under a dedicated result schema —
receives the verbatim answer, the triggering findings, and the ledger, and returns
per-finding mutations: `defer` (the finding transitions open → deferred) and `accept`
(open → accepted), each with an optional note, and `fix` (the finding stays open and
the answer directs its fix). Mutations SHALL target existing open findings only: ids
that are unknown or already terminal are no-ops, and adjudication SHALL NOT create
findings. The contract SHALL be one decision per finding: when the adjudication names
a finding id more than once, only its last mutation SHALL apply, so an applied `fix`
mutation always leaves its finding open and a pushed fix turn is always followed by a
review pass. The ask's prompt line, the verbatim answer, and the applied mutations SHALL
be recorded in the ledger's decisions record, and a decided finding's persisted
`needsHuman` flag SHALL be cleared. When the adjudication includes at least one `fix`
mutation, the answer text SHALL be sent verbatim as the next prompt of the
still-open work session (no header or framing added), and the commit-and-push step
SHALL follow (gated by dry-run as any fix). A decision-only answer (no `fix`
mutation) SHALL issue no work-session prompt and no commit-and-push. The iteration
SHALL count against the cap either way, and the loop SHALL continue toward
convergence; when a decision-only adjudication leaves no open blocking findings, the
loop SHALL converge immediately without a further review pass. When the human aborts
the ask, the operation SHALL fail with a distinct error stating the human aborted
the escalation. When no ask provider serves the request, the operation SHALL fail
with an error stating human input is needed to resolve the findings. An adjudication
session that submits no typed result SHALL be retried a bounded number of times, and
exhaustion SHALL fail the iteration — never a silent mutation.

The playbook's config SHALL accept `agent` and the required `judgeAgent` and
`reporterAgent` handles, `sessionConfig` (applied to every work session the playbook
creates), `judgeSessionConfig` (applied to every judge session and every adjudication
session), `reporterSessionConfig` (applied to every reporter session),
`reviewInstruction` (persona, per the instruction contract), `blockingAdditions`
(free text supplied to the judge defining what counts as blocking for the
repository), `dryRun`, and `maxIterations` (default 8). The `model` and `judgeModel`
config fields SHALL NOT exist: a model choice is an ordinary `sessionConfig` entry,
and the entry order is the consumer's `setConfig` order.

The `review` operation SHALL return a typed outcome carrying a status
(`converged` / `non-converged`), the final verdict text, the final ledger snapshot,
and the posted report text (`report`) — outcomes as data, matching the library's
transport conventions — rather than a bare verdict string. Escalation failures do not appear in the outcome: an
aborted or unservable ask fails the operation with an error, and an answered ask
continues the loop toward convergence, so the returned status is always
`converged` or `non-converged`.

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

- **WHEN** the judge's typed output reports open blocking findings and budget remains, and the judge flags `needsHuman` on no open blocking finding
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
- **THEN** the finding is recorded with a deferred status, the loop may converge with it open, the PR review report lists it under deferred findings, and it does not trigger an ask even when it carries `needsHuman`

#### Scenario: Deferred recurrence reconciles by id

- **WHEN** a later review pass flags a concern matching a deferred ledger finding
- **THEN** the judge's reconciliation reports it against the existing finding's id as still deferred, and the ledger records no duplicate entry for the same concern

#### Scenario: Non-blocking needsHuman does not ask

- **WHEN** the judge flags `needsHuman` on a non-blocking or deferred finding and open blocking findings exist
- **THEN** no ask is raised; the loop issues the batched fix turn for the open blocking findings, and the flagged concern's `needsHuman` determination is persisted in the ledger and rendered in the PR review report

#### Scenario: Unknown reconciliation id never escalates

- **WHEN** a reconciliation record flags `needsHuman` naming an id that matches no ledger finding
- **THEN** the record does not trigger an ask, and the loop proceeds by its convergence state alone

#### Scenario: Answer is adjudicated before any fix turn

- **WHEN** an ask is answered
- **THEN** a typed adjudication session returns per-finding mutations derived from the verbatim answer and the ledger, and the mutations are applied to the ledger before any work-session prompt is issued

#### Scenario: Human decision reaches the ledger

- **WHEN** the judge flags `needsHuman` on an open blocking finding and the ask is answered with a deferral for that finding
- **THEN** adjudication transitions the finding to deferred with the decision note, clears its `needsHuman` flag, records the ask's prompt line, the verbatim answer, and the mutations in the ledger's decisions record, issues no work-session prompt and no commit-and-push, and the loop does not re-ask the same finding

#### Scenario: Human escalation asks and resumes

- **WHEN** the judge flags `needsHuman` on an open blocking finding, an ask provider serves the request, and the human answers
- **THEN** the answer is adjudicated into typed ledger mutations before any fix turn; when the adjudication includes a `fix` mutation, the answer is sent verbatim as the next prompt of the still-open work session and the commit-and-push step follows (gated by dry-run as any fix); the iteration counts against the cap, and the loop continues toward convergence

#### Scenario: Decision-only adjudication converges immediately

- **WHEN** an adjudication applies only defer or accept mutations and leaves no open blocking findings
- **THEN** the loop converges without a further review pass, and the PR review report annotates the decided findings as maintainer decisions

#### Scenario: Adjudication mutations are inert on unknown or terminal ids

- **WHEN** the adjudication output names a finding id that is unknown or already terminal
- **THEN** no mutation is applied for that id and the loop proceeds

#### Scenario: Duplicate adjudication ids keep the last decision

- **WHEN** the adjudication returns more than one mutation for the same finding id
- **THEN** only the last mutation for that id is applied and recorded, and a `fix` for a finding the same batch defers or accepts issues no fix turn and no push

#### Scenario: Adjudication exhaustion fails the iteration

- **WHEN** the adjudication session submits no typed result on every attempt up to the bound
- **THEN** the iteration fails with a script error naming the adjudication session and the attempt count, and no ledger mutation is applied

#### Scenario: Ask carries identity, session label, ACP session id, and full probe text

- **WHEN** the loop raises an escalation ask
- **THEN** the prompt line identifies the loop, the PR URL, and the iteration state and names every triggering finding (id, family, severity, title), and the details carry the answer grammar (`defer <id>`, `accept <id>`, `fix: <instructions>`), the work session's label, the agent-side ACP session id, and the full review prose (the probe payload in this design) without truncation

#### Scenario: Human escalation abort fails

- **WHEN** the judge flags `needsHuman` on an open blocking finding, an ask provider serves the request, and the human aborts the ask
- **THEN** the operation fails with a distinct error stating the human aborted the escalation, and no fix is issued

#### Scenario: Unservable ask fails as before

- **WHEN** the judge flags `needsHuman` on an open blocking finding and no ask provider serves the request
- **THEN** the operation fails with an error stating human input is needed to resolve the findings — the same wording as before the ask existed — and no fix is issued

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
- **THEN** every judge session and every adjudication session receives the entries in declared order before its prompt

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
their id, family, severity, validation status, the judge's `needsHuman` determination,
status (`open` / `fixed` / `deferred` / `accepted`), and fixing commit where
applicable, the family table, and a decisions record. The decisions record SHALL
carry, for every answered ask in ask order (no timestamps), the ask's prompt line, the
verbatim answer, and the applied per-finding mutations with their notes. The ledger
SHALL be playbook-owned data; the documentation SHALL state that hand-editing it is
unsupported, that a deleted ledger degrades a fresh run to a new discovery pass
(today's per-run behavior), and that one loop per PR is an environment requirement
(two concurrent loops on one PR corrupt the in-place comment update).

A finding's `needsHuman` flag SHALL be recorded when the finding is filed, SHALL be
updated whenever a later reconciliation revisits the finding (the judge's latest
determination wins), and SHALL be cleared when an adjudicated decision records a
mutation for the finding (the human's determination supersedes the judge's). A ledger
written before the flag existed SHALL be read tolerantly: a finding without the field
is treated as not needing a human, and the field is written on the next persist.

Finding status SHALL be written by the reconciliation path (open → fixed when a fix
is verified clean) and the adjudication path (open → deferred, open → accepted, by
recorded human decision). Deferred and accepted are terminal: they have no exit
transitions, and a deferred concern that becomes in-scope again is filed as a new
open finding.

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
- **THEN** a ledger comment is created carrying the discovery SHA, the last reviewed SHA, the PR's intention, and the typed findings with their families, validation statuses, and `needsHuman` determinations

#### Scenario: needsHuman flag persists, updates, and clears

- **WHEN** a finding is filed with `needsHuman` flagged, a later reconciliation revisits the finding, and an adjudicated decision records a mutation for it
- **THEN** the ledger carries the judge's latest determination until the decision lands, then shows the flag cleared, and the PR review report renders the flag on undecided findings' lines and the maintainer-decision annotation on decided ones

#### Scenario: Decisions recorded on answered asks

- **WHEN** an ask is answered and adjudicated
- **THEN** the ledger's decisions record gains an entry carrying the ask's prompt line, the verbatim answer, and the applied mutations with their notes, ordered by ask with no timestamps

#### Scenario: Legacy ledgers read tolerantly

- **WHEN** the loop reads a ledger written before the `needsHuman` field and the decisions record existed
- **THEN** findings parse without the field and are treated as not needing a human, no decisions are assumed, and both are written on the next persist

#### Scenario: Fresh run resumes from the ledger

- **WHEN** a new `review` operation runs against a PR whose ledger comment exists (e.g. after a previous run ended at the cap)
- **THEN** the loop resumes from the ledger's state without a resume flag — open blocking findings drive a fix turn, a clean ledger at the current head converges immediately

#### Scenario: Ledger updated in place after each phase

- **WHEN** a review pass or fix turn completes
- **THEN** the ledger comment is updated in place (never appended as a new comment) reflecting the new `lastReviewedSha`, finding statuses, `needsHuman` flags, decisions, and family table

#### Scenario: Intention fallback

- **WHEN** the PR has no body at discovery time
- **THEN** the ledger's intention is captured from the last commit message before the first ledger record, and later passes reuse the cached intention

#### Scenario: Resolved findings compact

- **WHEN** a finding's fix has been verified clean in a later review pass
- **THEN** the ledger retains the finding as a terminal one-line entry with status `fixed` (id, title, family, fixing commit) rather than dropping it to a bare count, increments the resolved count, and no longer treats it as open — so the PR review report can list what was fixed

#### Scenario: One loop per PR is a documented requirement

- **WHEN** a consumer consults the playbook's documentation for environment requirements
- **THEN** the one-loop-per-PR requirement is stated alongside the `gh`-based PR-host requirement, and the documentation states the consequence of violating it (concurrent in-place ledger updates corrupting each other)
