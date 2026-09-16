## Context

The escalation decision lives in `anyNeedsHuman` (`playbooks/pr/playbook.luau:772`),
called in the loop after convergence and cap checks: any finding with `needsHuman` —
or any still-open reconciliation record with the flag — triggers the ask, regardless
of severity or status. `LedgerFinding` (`:60-70`) carries no `needsHuman`; the flag
exists only in the judge's typed output for the current pass. `ledgerSummary`
(`:501`) shows the judge only open findings, so deferred findings are invisible to
reconciliation and recurrences refile as duplicates. The convergence predicate
(`openBlockingCount`, `:476`) is `status == "open" and severity == "blocking"`; the
escalation predicate ignores both fields. On the respond branch, the answer goes
verbatim into the work session followed by an unconditional commit-and-push;
`applyFindings` — the only writer of finding status — runs solely on the
review→judge path, so a human decision can never reach the ledger (issue #13's
failure: PR #12's loop inverted a twice-given maintainer decision and reported
converged). Two grilling rounds settled the policy: the ask is exclusively a
convergence-gating instrument, and an answered ask must be adjudicated into typed
ledger mutations before any fix turn.

## Goals / Non-Goals

**Goals:**

- Make the escalation predicate a subset of the convergence predicate
  (`open` + `blocking` + `needsHuman`), for both new findings and reconciliation
  records.
- Route every answered ask through a typed adjudication pass whose mutations land in
  the ledger, with a recorded decision (prompt line, verbatim answer, mutations).
- Issue a fix turn only when the adjudication requests one; converge immediately
  when a decision-only adjudication clears the open blockers.
- Persist the `needsHuman` determination (updated on reconciliation, cleared on
  decision) so human-worthy non-blocking concerns stay visible in the durable record
  and report.
- Stop deferred recurrences from duplicating: the judge sees deferred ids and
  reconciles them as still deferred.

**Non-Goals:**

- Transitions *out of* `deferred` (e.g. `deferred → accepted` reclassification). A
  concern that becomes in-scope again is filed as a new open finding — correct
  behavior, at the cost of the old deferred ghost remaining.
- Per-finding fix attribution in `recordFixCommit` (it stamps every open blocking
  finding after any fix turn, human-guided included).
- The general empty-delta pass short-circuit (only the narrow decision-only
  immediate-converge is in scope).
- Ordering changes: escalate-first stays; the loop self-heals when an adjudicated
  fix addresses only some blockers.
- The ptah-repository offline suite (the library ships no test suite; the coverage
  contract lives there — see tasks for the coordination note).

## Decisions

**D1 — Predicate mirrors `openBlockingCount`, not raw severity.**
Escalate iff a finding is `status == "open" and severity == "blocking" and
needsHuman == true`. New-findings path: direct filter in the first loop of
`anyNeedsHuman` (renamed to reflect the gating, e.g. `anyBlockingNeedsHuman`).
Alternative rejected: gating on `severity == "blocking"` alone — a judge can emit
`blocking` + `deferred`, which `openBlockingCount` does not count; escalating on it
would re-create the divergence between the two predicates.

**D2 — Reconciliation records join against the ledger; unknown ids are inert.**
`JudgeReconciliation` carries no severity, so the second loop looks the record's id
up in `ledger.findings` and escalates only when that entry is open + blocking. A
record naming an absent id is silently ignored — escalation is the loop's most
expensive action, so an unverifiable reference errs toward not interrupting a human.
Alternative rejected: feeding unknown ids into the judge's bounded retry — grossly
malformed output already risks that path via the typed schema, and a single
hallucinated id does not warrant failing the pass.

**D3 — `needsHuman` is persisted; the latest determination wins, ending at the human.**
`LedgerFinding` gains `needsHuman: boolean`; `applyFindings` writes it on insertion
and updates it when a reconciliation record revisits the finding; an adjudicated
decision clears it (the human has decided — a lingering "needs human" would be
stale and misleading). `renderFinding` appends `, needs human` when true on
undecided findings. Reading tolerates the field's absence (legacy ledgers → false);
writing always includes it. Beyond the pass-local trigger, no logic reads the flag.

**D4 — Deferred dedup via visibility plus a reconciliation value; entries, not exits.**
`ledgerSummary` gains a deferred-findings section (ids, severity, family, title)
alongside the open one. The judge's reconciliation vocabulary gains `deferred`
(meaning still deferred): `priorFindingsStatus[].status` becomes
`"resolved" | "open" | "deferred"`, and the FINDINGS_SCHEMA enum follows.
`applyFindings` treats a `deferred` reconciliation as a no-op confirmation — the
entry stays, no duplicate is created, and the `needsHuman` flag updates per D3.
Deferred and accepted stay terminal: no exit transitions (settled follow-up), and
re-promotion is unnecessary — a context change is correctly expressed as a new open
finding. Adjudication (D8) adds *entry* transitions into deferred/accepted by human
decision only.

**D5 — Judge prompt states the interaction; code remains the guarantee.**
The Rules block adds: `needsHuman` is meaningful only on open blocking findings and
must not be set on deferred or non-blocking findings (human-worthy non-blocking
concerns go in the prose); the reconciliation rule gains the still-deferred outcome
and the deferred-recurrence rule. Belt and braces — the predicate enforces the
behavior even if the judge ignores the wording.

**D6 — Escalation-first ordering unchanged.** In a mixed pass (human-gated blocker +
mechanical blockers), the ask fires first; the adjudicated fix turn addresses what
the answer directs, and untouched mechanical blockers re-enter the batched fix on
the next iteration. Cheaper than a fix-first-then-escalate code path, at the cost of
at most one iteration in a rare case.

**D7 — The adjudicator is the judge agent under a dedicated schema.**
Adjudication runs as a fresh session (`pr-review-adjudicate:{iteration}`) on the
configured `judgeAgent` with `judgeSessionConfig` applied, carrying its own
`resultSchema` (the mutation contract). The judge is already the ledger's writer;
adjudication is the same trust role with a different prompt and schema. No new
config fields, no spec churn in the config surface. Alternatives rejected: a new
required `adjudicatorAgent` handle (config growth for a distinction nobody has
asked for; an ordinary follow-up if wanted), and the work session adjudicating its
own findings (re-creates the prose-is-the-record failure #13 documented). Malformed
output mirrors `runJudge`: typed schema, bounded retry, exhaustion fails the
iteration — never a silent mutation.

**D8 — Three mutations; retraction is a note.**
The adjudication contract returns per-finding mutations: `defer` (open → deferred),
`accept` (open → accepted) — each with an optional note — and `fix` (the finding
stays open; the answer directs its fix). #13's fourth verb, `retract`, is
structurally identical to `accept` (terminal, non-gating, no fix commit); the note
carries the nuance ("withdrawn as mistaken" vs "accepted as-is"). Mutations target
existing open findings only — unknown or terminal ids are no-ops, mirroring D2 —
and adjudication never creates findings.

**D9 — Adjudicate first; the fix turn is conditional.**
On `respond`: run the adjudication pass, apply its mutations, record the decision,
then — only if at least one `fix` mutation exists — send the answer verbatim to the
still-open work session followed by commit-and-push (dry-run gated). A decision-only
answer issues no session prompt and no push, eliminating #13's "nothing to commit"
no-op turns. The spec's verbatim-answer guarantee becomes scoped to fix requests.
The unit counts against the cap either way.

**D10 — Decision-only adjudication converges immediately.**
If the mutations leave no open blocking findings, converge without a further review
pass: the decision is recorded in the ledger, and a judge re-confirming it over an
empty delta buys a wasted pass, not correctness. Precedent: the resume path already
converges immediately on a clean ledger at the current head. The "every pushed fix
is followed by a review pass" invariant is untouched — nothing was pushed. The
general empty-delta optimization stays out (non-goal).

**D11 — The decisions record is prompt, answer, mutations — no timestamps.**
`Ledger` gains a `decisions` array; each entry carries the ask's prompt line, the
verbatim answer, and the applied mutations with notes. Array order is chronology
(asks are bounded by the iteration cap, so no compaction rule). No timestamps: the
ledger has none today, and nothing the loop reads needs them — the iteration state
rides in the prompt line. The reporter renders decided findings as maintainer
decisions ("Deferred (maintainer decision)" instead of #13's false "Deferred:
None"), and re-asking an already-decided finding is structurally impossible: the
decision moved it out of `open`, so the gated trigger's ledger join (D2) can no
longer fire for it.

**D12 — The ask names its findings and teaches the grammar.**
The prompt line names every triggering finding (id, family, severity, title); the
details open with the shorthands the adjudicator understands (`defer <id>`,
`accept <id>`, `fix: <instructions>`) before the session label, ACP session id, and
full review prose. #13's human spent 69 minutes inferring what "human input
required" wanted; naming f1 and accepting `defer f1` closes it in one line. The
adjudicator parses free text either way — the shorthands make the intent
unambiguous rather than relying on prose interpretation.

## Risks / Trade-offs

- [A judge ignores the prompt and flags `needsHuman` on a deferred finding] → the
  predicate ignores it (D1/D2); the worst case is a stale persisted flag in the
  report, not an interruption.
- [Human-worthy non-blocking concerns lose their mid-loop channel] → they gain a
  durable one instead: the persisted flag and the report's finding lines (D3). The
  review prose still carries them in the pass where they are raised.
- [The adjudicator misreads a free-text answer into the wrong mutation] → the typed
  schema bounds the damage to well-formed mutations; the verbatim answer is recorded
  beside them (D11), so a mis-adjudication is auditable and correctable by hand
  against the ledger's own record; the shorthands (D12) reduce the ambiguity the
  adjudicator faces.
- [Ledger JSON shape change breaks an external reader] → the ledger is
  playbook-owned by spec and hand-editing is unsupported; both fields are additive
  and optional on read. No migration needed beyond tolerant reading (D3/D11).
- [Deferred entries accumulate forever] → bounded by genuinely distinct concerns
  once duplicates stop (D4); accepted as the cost of "deferred is a parking lot."
- [`deferred` reconciliation value widens the judge's enum] → additive; a judge that
  never emits it loses dedup but nothing else, and the typed schema keeps it
  well-formed.
- [Immediate converge (D10) skips a judge confirmation of the decision] → the
  decision is human-authoritative and recorded; the alternative is the exact wasted
  pass #13 documented twice.

## Migration Plan

Pure library change on a branch; consumers pick it up via the pesde git dependency on
their next pin bump. Existing PR ledger comments read tolerantly (D3/D11) — no
operator action. Rollback is reverting the dependency pin.

## Open Questions

None — two grilling rounds settled the design tree; the defaults taken there
(reconciliation value named `deferred`; flag updates on reconciliation and clears on
decision; retraction folded into `accept`) are recorded in D3, D4, and D8.
