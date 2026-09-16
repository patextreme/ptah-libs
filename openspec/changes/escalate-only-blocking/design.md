## Context

The escalation decision lives in `anyNeedsHuman` (`playbooks/pr/playbook.luau:772`),
called in the loop after convergence and cap checks: any finding with `needsHuman` —
or any still-open reconciliation record with the flag — triggers the ask, regardless
of severity or status. `LedgerFinding` (`:60-70`) carries no `needsHuman`; the flag
exists only in the judge's typed output for the current pass. `ledgerSummary`
(`:501`) shows the judge only open findings, so deferred findings are invisible to
reconciliation and recurrences refile as duplicates. The convergence predicate
(`openBlockingCount`, `:476`) is `status == "open" and severity == "blocking"`; the
escalation predicate ignores both fields. The grilling session settled the policy:
the ask is exclusively a convergence-gating instrument; the report is the channel for
everything else.

## Goals / Non-Goals

**Goals:**

- Make the escalation predicate a subset of the convergence predicate
  (`open` + `blocking` + `needsHuman`), for both new findings and reconciliation
  records.
- Persist the `needsHuman` determination in the ledger, updated on reconciliation, so
  human-worthy non-blocking concerns stay visible in the durable record and report.
- Stop deferred recurrences from duplicating: the judge sees deferred ids and
  reconciles them as still deferred.
- Keep the change single-mechanism: no new statuses, no transitions, no loop-shape
  changes.

**Non-Goals:**

- Transitions out of `deferred` (e.g. `deferred → accepted` reclassification). A
  concern that becomes in-scope again is filed as a new open finding — correct
  behavior, at the cost of the old deferred ghost remaining.
- Per-finding fix attribution in `recordFixCommit` (it stamps every open blocking
  finding after any fix turn, human-guided included).
- Ordering changes: escalate-first stays; the loop self-heals when a human answer
  fixes only some blockers (the next pass batch-fixes the rest).
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

**D3 — `needsHuman` is persisted, last determination wins.**
`LedgerFinding` gains `needsHuman: boolean`; `applyFindings` writes it on insertion
and updates it when a reconciliation record revisits the finding (resolved findings
keep their flag as filed — historical record). `renderFinding` appends `,
needs human` when true. Reading tolerates the field's absence (legacy ledgers →
false); writing always includes it. The persisted flag is display-only: no logic
beyond the pass-local trigger reads it.

**D4 — Deferred dedup via visibility plus a reconciliation value, no transitions.**
`ledgerSummary` gains a deferred-findings section (ids, severity, family, title)
alongside the open one. The judge's reconciliation vocabulary gains `deferred`
(meaning still deferred): `priorFindingsStatus[].status` becomes
`"resolved" | "open" | "deferred"`, and the FINDINGS_SCHEMA enum follows.
`applyFindings` treats a `deferred` reconciliation as a no-op confirmation — the
entry stays, no duplicate is created, and the `needsHuman` flag updates per D3.
Alternatives rejected: (a) transitions out of deferred (settled as a follow-up in
the grilling); (b) re-promotion `deferred → open` (a context change is correctly
expressed as a new open finding).

**D5 — Judge prompt states the interaction; code remains the guarantee.**
The Rules block adds: `needsHuman` is meaningful only on open blocking findings and
must not be set on deferred or non-blocking findings (human-worthy non-blocking
concerns go in the prose); the reconciliation rule gains the still-deferred outcome
and the deferred-recurrence rule. Belt and braces — the predicate enforces the
behavior even if the judge ignores the wording.

**D6 — Escalation-first ordering unchanged.** In a mixed pass (human-gated blocker +
mechanical blockers), the ask fires first and the human's single answer is the fix
turn; untouched mechanical blockers re-enter the batched fix on the next iteration.
Cheaper than a fix-first-then-escalate code path, at the cost of at most one
iteration in a rare case.

## Risks / Trade-offs

- [A judge ignores the prompt and flags `needsHuman` on a deferred finding] → the
  predicate ignores it (D1/D2); the worst case is a stale persisted flag in the
  report, not an interruption.
- [Human-worthy non-blocking concerns lose their mid-loop channel] → they gain a
  durable one instead: the persisted flag and the report's finding lines (D3). The
  review prose still carries them in the pass where they are raised.
- [Ledger JSON shape change breaks an external reader] → the ledger is
  playbook-owned by spec and hand-editing is unsupported; the field is additive and
  optional on read. No migration needed beyond tolerant reading (D3).
- [Deferred entries accumulate forever] → bounded by genuinely distinct concerns
  once duplicates stop (D4); accepted as the cost of "deferred is a parking lot."
- [`deferred` reconciliation value widens the judge's enum] → additive; a judge that
  never emits it loses dedup but nothing else, and the typed schema keeps it
  well-formed.

## Migration Plan

Pure library change on a branch; consumers pick it up via the pesde git dependency on
their next pin bump. Existing PR ledger comments read tolerantly (D3) — no operator
action. Rollback is reverting the dependency pin.

## Open Questions

None — the grilling session settled the design tree; the two defaults taken there
(reconciliation value named `deferred`; flag updates on reconciliation) are recorded
in D3/D4.
