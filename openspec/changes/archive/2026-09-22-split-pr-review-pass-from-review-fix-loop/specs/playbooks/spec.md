# Spec Delta

## REMOVED Requirements

### Requirement: PR review loop playbook

**Reason**: The monolithic requirement conflated two operations that this
change splits: the single review pass and the convergent loop. One
requirement cannot name both operations' contracts without ambiguity about
which operation owns which behavior.

**Migration**: The loop's contract moves whole into the new "PR review-fix
loop" requirement (`reviewFixLoop`); the per-pass machinery it shared moves
into the new "PR review pass" requirement (`review`). Consumers pin the
prior tag to defer the breaking rename.

## ADDED Requirements

### Requirement: PR review pass

The library SHALL provide a PR review pass operation (`review`) on the pr
playbook: exactly one review pass against a pull request that never fixes.
The target repository SHALL NOT be playbook config: it arrives per call
inside the PR URL. The playbook SHALL NOT read CI results or execute
repo-specific gate commands; deterministic signal ingestion and post-review
policy are the calling script's responsibility. The playbook SHALL document
this boundary. The operation shares one `Config` with the review-fix loop
(below): `agent`, the required `judgeAgent` and `reporterAgent` handles,
`sessionConfig`, `judgeSessionConfig`, `reporterSessionConfig`,
`reviewInstruction`, `blockingAdditions`, `workingDir`, `dryRun`, and
`maxIterations`. The `model` and `judgeModel` config fields SHALL NOT
exist: a model choice is an ordinary `sessionConfig` entry.

The pass SHALL run unconditionally. With no existing ledger it runs a
discovery pass: a full-PR review whose result creates the ledger with the
discovery SHA, the `lastReviewedSha`, and the PR's intention (the PR title
and body when present; otherwise the last commit message before the first
ledger record, captured at discovery). With an existing ledger it runs a
delta review: the review prompt carries the ledger's `lastReviewedSha` and
directs the reviewer to review only the changes since that commit and to
report recurrences by ledger finding id rather than refiling them. No
ledger state SHALL gate or skip the pass — it runs even when the
`lastReviewedSha` equals the current head (deleting the ledger is the
documented re-review escape hatch).

The work session reviews freely in prose following its persona instruction
and SHALL validate blocking findings with its own in-session subagents
before finalizing its review; the directive SHALL be carried by the
component-owned protocol fragment, not the configurable persona, so a
persona replacement cannot remove it. The playbook SHALL convert the work
session's prose into structured data through a typed judge session (a
`resultSchema` result): the judge SHALL receive the review prose, the
ledger state (open and deferred findings with their ids), the PR's
intention, and the configured `blockingAdditions` text, and SHALL return
typed findings carrying per-finding severity (blocking or non-blocking), a
family name, a validation status, and the judge's `needsHuman`
determination, together with a reconciliation of the ledger's findings —
resolved (with evidence), still open, or still deferred — covering both
open and deferred entries. The judge SHALL steer findings against the PR's
intention: a finding the judge rates important but outside the PR's scope
SHALL be recorded with a deferred status in the ledger, SHALL NOT gate
convergence, and SHALL be surfaced in the PR review report's deferred
list. A recurrence of a deferred finding SHALL be reported against that
finding's id as still deferred, never refiled as a new finding. A judge
that submits no typed result SHALL be retried a bounded number of times,
and exhaustion SHALL fail the operation with a script error naming the
judge and the attempt count — never a silent outcome. The judge agent is a
required config handle: no prose-parsing fallback replaces it.

The pass SHALL apply the judge's output to the ledger exactly as the
review-fix loop does — filing open or deferred, reconciling (open → fixed
on verified-clean evidence; the judge's latest `needsHuman` determination
wins and never clears), retaining terminal `fixed` entries — and SHALL
persist the ledger in place after the pass.

The pass SHALL NOT fix, commit, or push; it SHALL NOT ask a human at any
point. `dryRun` and `maxIterations` SHALL be inert for the pass (loop-only
knobs, documented as such). After the ledger is persisted the pass SHALL
produce a PR review report per the PR review report requirement, and SHALL
return a typed outcome carrying a status (`converged` when no open
blocking findings remain after the pass, `non-converged` otherwise), the
pass's verdict prose as `verdict` (always populated — the pass always runs
one), the final ledger snapshot, and the posted report text (`report`).

#### Scenario: No ledger runs discovery

- **WHEN** `review` is called on a PR with no existing ledger
- **THEN** one full-PR review pass runs, and the result creates the ledger with the discovery SHA, the `lastReviewedSha`, and the PR's intention

#### Scenario: Existing ledger runs a delta pass

- **WHEN** `review` is called on a PR whose ledger exists
- **THEN** one delta review pass runs — the prompt carries the ledger's `lastReviewedSha` and directs the reviewer to review only the changes since that commit and to report recurrences by ledger finding id — and the ledger's `lastReviewedSha` advances to the reviewed head

#### Scenario: The pass runs even against a reviewed head

- **WHEN** `review` is called and the ledger's `lastReviewedSha` already equals the current head
- **THEN** the delta pass runs anyway (no skip fast path), the ledger persists, and a report is produced — deleting the ledger is the documented way to force a fresh discovery

#### Scenario: The pass never fixes

- **WHEN** a pass ends with open blocking findings in the ledger
- **THEN** no fix prompt is issued, nothing is committed or pushed, the outcome is `non-converged`, and the report leads with the open blocking findings

#### Scenario: Judge exhaustion fails the operation

- **WHEN** the judge session submits no typed result on every attempt up to the bound
- **THEN** the operation fails with a script error naming the judge and the attempt count, and no report is produced

#### Scenario: Deferred findings do not gate the outcome

- **WHEN** the judge defers a finding as important but outside the PR's intention
- **THEN** the finding is recorded with a deferred status, the outcome may be `converged` with it open, and the PR review report lists it under deferred findings

#### Scenario: Repository context is per-call

- **WHEN** `review` reviews a pull request
- **THEN** the repository context comes from the PR URL passed to the operation, and the playbook's config declares no repository field

#### Scenario: Loop-only knobs are inert

- **WHEN** `review` runs with `dryRun` or `maxIterations` configured
- **THEN** the pass behaves identically — it never pushes and never loops, so the knobs have no pass effect

#### Scenario: Work sessions receive session config

- **WHEN** the playbook is configured with `sessionConfig` entries and `review` runs
- **THEN** the pass's work session receives the entries in declared order before its prompt

#### Scenario: Judge sessions receive judge session config

- **WHEN** the playbook is configured with `judgeSessionConfig` entries and `review` runs
- **THEN** the pass's judge session receives the entries in declared order before its prompt

#### Scenario: Removed model field is a type error

- **WHEN** a consumer shim configures the removed `model` or `judgeModel` field and runs `ptah check`
- **THEN** check reports a type error naming the unknown field, steering the consumer to the `sessionConfig` entry form

### Requirement: PR review-fix loop

The library SHALL provide a review-fix loop operation (`reviewFixLoop`) on
the pr playbook: the convergent review→validate→fix loop composed from
review passes (per the PR review pass requirement, whose prompt, judge,
ledger, and report machinery it shares) and fix turns. The playbook SHALL
NOT read CI results or execute repo-specific gate commands; deterministic
signal ingestion and post-loop policy are the calling script's
responsibility, and the playbook SHALL document this boundary.

Convergence SHALL be computed from the judge's typed output: the loop
converges when no open blocking findings remain. The loop's budget is a
single `maxIterations` cap (default 8) over review passes. A fix turn
SHALL be issued only when open blocking findings exist and budget remains;
when the cap is reached with open findings, the loop SHALL NOT fix — it
SHALL end and report a non-converged outcome. Every pushed fix is
therefore followed by at least one review pass. A fix turn SHALL address
all open blocking findings in one turn, by root cause, and SHALL commit
and push (gated by `dryRun`). Deferred findings never gate convergence.

The work session SHALL NOT post to the pull request. For every terminal
outcome that returns (converged or non-converged), the operation SHALL
produce a PR review report per the PR review report requirement.

The loop SHALL NOT ask a human at any point: the pull request itself,
reviewed by its human at merge time, is the loop's human checkpoint. The
judge's `needsHuman` flag is report-only: the judge SHALL set it only on
an open blocking finding that rests on an operator-owned decision — one
the agent has no authority to take — that a human should examine at
review; the flag SHALL NOT be set on a deferred or non-blocking finding.
The flag persists in the ledger, renders on the finding's line in the PR
review report, and never gates, pauses, or fails the loop: an open
blocking finding carrying `needsHuman` is fixed autonomously like any
other blocking finding. A `needsHuman` determination on a non-blocking or
deferred finding, and a reconciliation record naming an id absent from the
ledger, have no loop effect: the determination persists and renders in the
report. No ask is raised, so no ask can be refused, abort, or fail for
lack of a provider: a provider-less environment behaves identically to a
served one, and the report comment is the loop's only human-facing
channel. The ledger's only writers are filing (open or deferred),
reconciliation (resolved or updated), and verification (fixed); no
mid-run path writes finding status by human decision, and no decisions
record is written (legacy decisions records are read tolerantly and
dropped on persist).

The `reviewFixLoop` operation SHALL return a typed outcome carrying a
status (`converged` / `non-converged`), the final verdict text, the final
ledger snapshot, and the posted report text (`report`).

#### Scenario: Loop composes passes and fix turns

- **WHEN** `reviewFixLoop` runs against a PR whose review leaves open blocking findings with budget remaining
- **THEN** one batched fix turn addresses all open blocking findings by root cause and commits and pushes (gated by `dryRun`), followed by another review pass, iterating until convergence or the cap

#### Scenario: First pass reviews the whole PR

- **WHEN** the loop reviews a PR with no existing ledger
- **THEN** the first review pass is a discovery pass per the PR review pass requirement

#### Scenario: Later passes review only the delta

- **WHEN** the loop runs a review pass after a fix has been pushed
- **THEN** that pass is a delta review per the PR review pass requirement

#### Scenario: Convergence is computed from typed findings

- **WHEN** the judge's typed output reports no open blocking findings
- **THEN** the loop converges and the playbook produces a PR review report whose status line reports convergence

#### Scenario: Fix never consumes the last unit

- **WHEN** the judge reports open blocking findings and the iteration cap has been reached
- **THEN** no fix turn is issued; the loop ends, the operation returns a non-converged outcome carrying the verdict text, the ledger snapshot, and the report text, and the playbook produces a non-converged PR review report

#### Scenario: Resume fast path fixes open blockers

- **WHEN** a fresh `reviewFixLoop` operation resumes a ledger holding open blocking findings — including any carrying `needsHuman` — and budget remains
- **THEN** the resume fast path issues the fix turn for them like any other open blocking finding, without an ask — the flag is the reviewer's pointer, not a gate

#### Scenario: Resume fast path converges a clean ledger at head

- **WHEN** a fresh `reviewFixLoop` operation resumes a ledger with no open blocking findings whose `lastReviewedSha` equals the current head
- **THEN** no work session runs; the report is produced from the ledger alone (no review prose) and the outcome is `converged`

#### Scenario: Resume at the cap ends without a pass

- **WHEN** a fresh `reviewFixLoop` operation resumes a ledger holding open blocking findings and the cap is already exhausted
- **THEN** no review pass and no fix turn run; the operation returns non-converged and the report renders from the ledger alone

#### Scenario: needsHuman is report-only

- **WHEN** the judge flags `needsHuman` on an open blocking finding
- **THEN** the loop issues the fix turn for it like any other blocking finding, no ask is raised, the flag persists in the ledger, and the PR review report renders it on the finding's line for the reviewing human

#### Scenario: Non-blocking needsHuman does not ask

- **WHEN** the judge flags `needsHuman` on a non-blocking or deferred finding and open blocking findings exist
- **THEN** no ask exists to raise — the loop issues the batched fix turn for the open blocking findings, and the flagged concern's `needsHuman` determination is persisted in the ledger and rendered in the PR review report

#### Scenario: Unknown reconciliation id never escalates

- **WHEN** a reconciliation record flags `needsHuman` naming an id that matches no ledger finding
- **THEN** the record has no loop effect — no ask exists to trigger — and the loop proceeds by its convergence state alone

#### Scenario: Human decision reaches the ledger only at review time

- **WHEN** a human reviews the PR after a loop run
- **THEN** human decisions land at PR review time — the merge review, guided by the report's `needsHuman` flags — never in the ledger mid-run; legacy decisions records are read tolerantly and no new ones are written

#### Scenario: The loop never asks

- **WHEN** the loop runs to a terminal outcome in any environment — with or without an ask provider
- **THEN** no ask is raised, so no ask can be refused, abort, or fail for lack of a provider; the report comment is the only human-facing channel, and it carries the ledger, the flags, and the prose

#### Scenario: Judge exhaustion fails the iteration

- **WHEN** the judge session submits no typed result on every attempt up to the bound
- **THEN** the iteration fails with a script error naming the judge and the attempt count, and no fix turn is issued

#### Scenario: Config surface

- **WHEN** a consumer constructs the playbook
- **THEN** the config is the single shared surface per the PR review pass requirement, with `maxIterations` defaulting to 8 and `dryRun` defaulting to false for the loop

#### Scenario: Operation returns a typed outcome

- **WHEN** the `reviewFixLoop` operation ends — converged, or non-converged at the cap
- **THEN** the operation returns a typed outcome carrying the status (`converged` / `non-converged`), the final verdict text, the final ledger snapshot, and the report text, rather than only a verdict string

## MODIFIED Requirements

### Requirement: PR review report

The pr playbook SHALL produce a **PR review report** — a human-facing
summary of a PR review operation (one review pass or a whole review-fix
loop) — as a pull-request comment marked
`<!-- ptah:pr-review-report -->` and edited in place across runs, for every
terminal outcome of a `review` or `reviewFixLoop` operation that returns
(converged and non-converged). An operation that fails — reporter
exhaustion — SHALL NOT produce a report.

The report SHALL be authored by a dedicated reporter agent: a required
`reporterAgent` config handle and an optional `reporterSessionConfig`
(applied to every reporter session in declared order). Both operations
run the reporter through the same configured handle; every call creates a
fresh reporter session. The reporter SHALL submit a typed result (a
`resultSchema` result) carrying the report body. The playbook SHALL retry
a reporter that submits no typed result a bounded number of times, and
exhaustion SHALL fail the operation with an error naming the reporter and
the attempt count — never a silent absence of the report. The converged
work session SHALL NOT author or post the report.

The playbook SHALL post and edit the report through the library's GitHub
transport, matching the ledger's marker-and-edit pattern, so a re-run —
of either operation — edits the existing report rather than appending
another: one ever-current report; the ledger carries the history. The
playbook SHALL prepend a deterministic status line derived from the ledger
— the outcome status and the count of open blocking findings — so the
report's convergence claim is never agent-authored. The reporter SHALL
author the remainder of the body under a playbook-defined section
contract.

The report body SHALL cover: the PR's intention; the resolved findings as
one-line entries; the open non-blocking findings; the deferred findings;
the accepted findings (legacy ledgers only — no new run produces them);
and a **review summary** (the operation's pass count — one for a `review`
pass, the loop's completed units for `reviewFixLoop` — plus the discovery
and last-reviewed SHAs, and the family table). For a non-converged outcome
the report SHALL lead with an open blocking findings section beneath the
status line. The resolved findings list SHALL be capped at 50 entries with
a note of how many earlier entries are omitted, so the report stays
readable while the ledger retains every entry.

The reporter session SHALL receive the full ledger, the terminal status,
and the required section contract, so the report reflects the ledger
rather than the last delta alone. It SHALL additionally receive the last
review pass's prose when a review pass ran in the current operation —
always for `review` (the pass always runs), and for `reviewFixLoop` unless
a resume converged immediately or ended at the cap without a new review
pass, in which case the prompt carries an explicit no-prose marker and the
report is rendered from the ledger alone. The ledger is the durable
whole-loop source; the prose is supplementary.

#### Scenario: Report produced on convergence

- **WHEN** a review pass converges and the operation returns
- **THEN** the playbook posts a PR review report whose status line reports convergence and whose body covers the ledger's resolved, open non-blocking, deferred, and accepted findings and the review summary

#### Scenario: Report produced on cap and leads with blockers

- **WHEN** the loop reaches the cap with open blocking findings and returns a non-converged outcome
- **THEN** the playbook posts a PR review report whose status line reports non-convergence and the open blocking count, and whose body leads with an open blocking findings section

#### Scenario: Report produced for a lone pass

- **WHEN** a `review` operation returns — converged or not
- **THEN** the playbook produces the same-shaped PR review report, with the review summary carrying a pass count of one

#### Scenario: Report is edited in place across runs

- **WHEN** a `review` or `reviewFixLoop` operation runs against a PR that already has a report comment
- **THEN** the playbook edits that comment in place rather than appending a second report

#### Scenario: Playbook owns the status line

- **WHEN** the report is produced for any outcome of either operation
- **THEN** the status line naming the outcome status and the open blocking count is composed by the playbook from the ledger, not by the reporter

#### Scenario: Reporter exhaustion fails the operation

- **WHEN** the reporter session submits no typed result on every attempt up to the bound
- **THEN** the operation fails with a script error naming the reporter and the attempt count, and no report is posted

#### Scenario: Reporter receives the full ledger and the last review prose

- **WHEN** the playbook prompts the reporter after a review pass ran in the current operation
- **THEN** the prompt carries the full ledger (including retained `fixed` entries), the terminal status, the last review pass's prose, and the section contract

#### Scenario: Reporter runs without prose on a resume

- **WHEN** a `reviewFixLoop` operation returns without running a new review pass — an immediate resume converge, or a resumed ledger already at the cap — and a report is produced
- **THEN** the reporter prompt carries the full ledger, the terminal status, and the section contract with an explicit no-prose marker instead of review prose, and the operation still returns `outcome.report`

#### Scenario: Reporter session config is applied

- **WHEN** the playbook is configured with `reporterSessionConfig` entries and a report is produced by either operation
- **THEN** the reporter session receives the entries in declared order before its prompt

#### Scenario: Resolved list is capped

- **WHEN** the ledger holds more than 50 retained `fixed` entries
- **THEN** the report's resolved section lists 50 and notes how many earlier entries are omitted, while the ledger continues to retain every entry

### Requirement: PR review ledger

The pr playbook SHALL persist its review state as a ledger stored in a
dedicated pull-request comment (marked
`<!-- ptah:pr-review-ledger -->` and updated in place through the library's
GitHub transport), not in playbook config or local state. The ledger SHALL
carry: the PR identity, the discovery SHA and the `lastReviewedSha`, the
PR's intention (the PR title and body when present; otherwise the last
commit message before the first ledger record, captured at discovery), the
findings with their id, family, severity, validation status, the judge's
`needsHuman` determination, status (`open` / `fixed` / `deferred` /
`accepted`), and fixing commit where applicable, and the family table. The
ledger SHALL be playbook-owned data; the documentation SHALL state that
hand-editing it is unsupported, that a deleted ledger degrades a fresh run
to a new discovery pass (today's per-run behavior), and that one
operation per PR at a time is an environment requirement (two concurrent
operations on one PR corrupt the in-place comment update). Legacy ledgers
carrying a decisions record SHALL be read tolerantly; no new decisions are
recorded.

A finding's `needsHuman` flag SHALL be recorded when the finding is filed,
SHALL be updated whenever a later reconciliation revisits the finding (the
judge's latest determination wins), and never clears — there is no mid-loop
human decision to supersede it. A ledger written before the flag existed
SHALL be read tolerantly: a finding without the field is treated as not
needing a human, and the field is written on the next persist.

Finding status SHALL be written by the judge at filing (open, or deferred
for out-of-scope concerns) and by the reconciliation path (open → fixed
when a fix is verified clean). Deferred is terminal: it has no exit
transitions, and a deferred concern that becomes in-scope again is filed
as a new open finding. `accepted` is a legacy status: read tolerantly,
terminal, and no new transition writes it (its only writer was the retired
adjudication path).

A fresh `reviewFixLoop` operation SHALL resume automatically from an
existing ledger without a resume flag: no ledger means a fresh discovery
pass; an existing ledger means the loop continues from its state (open
blocking findings — regardless of any `needsHuman` flag — drive a fix
turn; a clean ledger at the current head converges). The `review`
operation takes no resume path at all: it runs its single pass
unconditionally — discovery when no ledger exists, a delta pass otherwise
— regardless of ledger state.

Once a finding's fix has been verified clean in a later review pass, the
playbook SHALL retain it as a terminal one-line entry with status `fixed`
— its id, title, family, and fixing commit — and increment the resolved
count, rather than collapsing it to a bare count, so the PR review report
can list what was fixed. A `fixed` entry no longer participates in
reconciliation and never gates convergence. Retaining fixed entries means
the ledger grows with the PR; a ledger that outgrows the platform comment
limit fails loudly through the transport rather than truncating.

#### Scenario: Ledger created at discovery

- **WHEN** the first review pass completes on a PR with no ledger comment
- **THEN** a ledger comment is created carrying the discovery SHA, the last reviewed SHA, the PR's intention, and the typed findings with their families, validation statuses, and `needsHuman` determinations

#### Scenario: needsHuman flag persists, updates, and clears

- **WHEN** a finding is filed with `needsHuman` flagged and a later reconciliation revisits the finding
- **THEN** the ledger carries the judge's latest determination and the flag never clears — no mid-loop human decision exists to supersede it — and the PR review report renders it on the finding's line

#### Scenario: Legacy ledgers read tolerantly

- **WHEN** the playbook reads a ledger written before the `needsHuman` field existed, or one carrying a decisions record or `accepted` findings from before the ask was retired
- **THEN** findings parse without the field and are treated as not needing a human, decisions are ignored, `accepted` findings stay terminal, and the flag field is written on the next persist

#### Scenario: Decisions recorded on answered asks

- **WHEN** the playbook reads a ledger carrying a decisions record from before the ask was retired
- **THEN** no new decisions are recorded — the decisions record is never written; legacy entries are read tolerantly and dropped on the next persist

#### Scenario: Fresh run resumes from the ledger

- **WHEN** a new `reviewFixLoop` operation runs against a PR whose ledger comment exists (e.g. after a previous run ended at the cap)
- **THEN** the loop resumes from the ledger's state without a resume flag — open blocking findings (flagged or not) drive a fix turn, a clean ledger at the current head converges immediately

#### Scenario: One loop per PR is a documented requirement

- **WHEN** a consumer consults the playbook's documentation for environment requirements
- **THEN** the requirement is stated as one operation per PR at a time — a lone `review` pass corrupts in-place comment writes exactly like a loop — alongside the `gh`-based PR-host requirement, with the consequence of violating it (concurrent in-place ledger updates corrupting each other)

#### Scenario: Pass advances the ledger without a resume path

- **WHEN** a `review` operation runs against a PR whose ledger comment exists
- **THEN** the pass runs unconditionally as a delta review per the PR review pass requirement — no ledger state skips it and no fix turn precedes it

#### Scenario: Ledger updated in place after each phase

- **WHEN** a review pass or fix turn completes
- **THEN** the ledger comment is updated in place (never appended as a new comment) reflecting the new `lastReviewedSha`, finding statuses, `needsHuman` flags, and family table

#### Scenario: Intention fallback

- **WHEN** the PR has no body at discovery time
- **THEN** the ledger's intention is captured from the last commit message before the first ledger record, and later passes reuse the cached intention

#### Scenario: Resolved findings compact

- **WHEN** a finding's fix has been verified clean in a later review pass
- **THEN** the ledger retains the finding as a terminal one-line entry with status `fixed` (id, title, family, fixing commit) rather than dropping it to a bare count, increments the resolved count, and no longer treats it as open — so the PR review report can list what was fixed



### Requirement: PR review instruction contract

The pr playbook's documentation SHALL declare a three-layer instruction
contract, identical for both operations — every review prompt of `review`
and `reviewFixLoop` carries the same persona and protocol layers. The
**persona** layer is the reviewer instruction: a configured
`reviewInstruction` is a full replacement of the built-in default persona
(only a nil value selects the default; an empty string stays configured as
a loud misconfiguration) and carries no classification duties — the
reviewer reviews freely in prose. The **protocol** layer is a
component-owned instruction fragment appended to every review prompt at
runtime and not configurable away: the delta-review rules, the in-session
validation directive, the report-recurrences-by-ledger-id rule, and family
reuse-or-justify guidance. The **taxonomy** layer is the judge's: what
counts as blocking for the repository arrives through the
`blockingAdditions` config field (free text supplied to the judge), not
through the reviewer instruction, so the structure of either operation is
not sensitive to the quality or format of a repo-authored instruction.

The playbook's config surface (the exported `Config` type's doc comments
for `reviewInstruction` and `blockingAdditions`) SHALL state each field's
layer and role, and SHALL state which knobs are loop-only (`dryRun`,
`maxIterations`) — inert for `review`. The documentation SHALL also state
the playbook's boundary: verdicts that do not reduce to a
blocking/non-blocking classification (score gates, approve/request-changes
votes, report-only reviews) are a different playbook, not an instruction
swap, and deterministic signals (CI checks, configured gates) are outside
the playbook — they belong to the calling script.

The documentation SHALL present pointer-style instructions — reviewer
instruction text that references a repository document — as the
recommended form when the instruction is long or repo-pinned, noting that
configured text is inlined into every review prompt.

The playbook SHALL ship a built-in default persona instruction and SHALL
use it when no reviewer instruction is configured; the default carries no
classification directive (classification belongs to the judge).

#### Scenario: Instruction contract is declared

- **WHEN** a consumer consults the pr playbook's documentation before supplying a reviewer instruction
- **THEN** the three layers (persona configurable, protocol appended and not configurable away, taxonomy owned by the judge plus `blockingAdditions`) are stated, along with the boundary that verdicts not reducible to a blocking/non-blocking classification belong to a different playbook

#### Scenario: Config surface states the classification requirement

- **WHEN** a consumer reads the exported `Config` type for the pr playbook
- **THEN** `reviewInstruction`'s documentation states it is the persona (full replacement; nil selects the built-in default) with no classification duties, `blockingAdditions`' documentation states it is the judge-facing blocking taxonomy for the repository, and the loop-only knobs are marked inert for `review`

#### Scenario: Built-in default instruction used when none is configured

- **WHEN** the playbook is configured without `reviewInstruction` (the field is nil)
- **THEN** reviews run against the playbook's built-in default persona instruction, which carries no blocking/non-blocking classification directive (classification belongs to the judge)

#### Scenario: Configured instruction takes precedence

- **WHEN** `reviewInstruction` is configured with instruction text
- **THEN** the built-in default is not used — the configured text is inlined into the review prompt as the persona, the protocol fragment is still appended, and the judge still supplies the taxonomy regardless of the configured text

#### Scenario: Protocol is not configurable away

- **WHEN** any review pass runs — a lone `review` pass or a pass inside `reviewFixLoop` — with a configured persona or the built-in default
- **THEN** the review prompt carries the component-owned protocol fragment (delta rules, in-session validation directive, recurrence-by-ledger-id, family reuse guidance) in addition to the persona

#### Scenario: Pointer pattern is the documented long form

- **WHEN** a consumer consults the pr playbook's documentation with a long or repo-pinned reviewer instruction in mind
- **THEN** the documentation presents pointer-style text referencing a repository document as the recommended form
