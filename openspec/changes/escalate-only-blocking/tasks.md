## 1. Ledger schema and persistence

- [ ] 1.1 Add `needsHuman: boolean` to `LedgerFinding` in `playbooks/pr/playbook.luau`, copy it in `applyFindings` on insertion, and update it when a reconciliation record revisits the finding — verify with `ptah check` and by reading the persisted ledger JSON of a scratch run
- [ ] 1.2 Make ledger reading tolerant of the field's absence (legacy ledgers parse as `needsHuman = false`) and always write the field on persist — verify by hand-loading a pre-change ledger JSON (e.g. PR #14's) through `readLedger` in a scratch `ptah run` script and checking the re-persisted comment carries the flag

## 2. Gated escalation predicate

- [ ] 2.1 Rename `anyNeedsHuman` to a gating name (e.g. `anyBlockingNeedsHuman`), filter new findings on `status == "open" and severity == "blocking" and needsHuman`, and join reconciliation records by id against `ledger.findings` (open + blocking only; unknown ids never escalate) — verify with `ptah check` and a scratch judge fixture run whose typed output flags `needsHuman` on a deferred finding only: no ask is raised
- [ ] 2.2 Render the persisted flag in `renderFinding` (append `, needs human` when true) and confirm the PR review report requirement's finding-line contract still holds by inspecting a scratch run's posted report text

## 3. Deferred dedup

- [ ] 3.1 Extend `ledgerSummary` with a deferred-findings section (id, severity, family, title) so the judge sees deferred ids alongside open ones — verify the judge prompt text of a scratch run lists a deferred finding by id
- [ ] 3.2 Add `"deferred"` to the reconciliation status enum in `JudgeReconciliation` and `FINDINGS_SCHEMA`, and handle it in `applyFindings` as a no-op confirmation (no duplicate entry; `needsHuman` still updates per task 1.1) — verify a scratch run whose judge reports a deferred recurrence against the existing id creates no new ledger entry

## 4. Judge prompt rules

- [ ] 4.1 Edit the Rules block in `buildJudgePrompt`: `needsHuman` meaningful only on open blocking findings (never on deferred or non-blocking; human-worthy non-blocking concerns go in the prose), the reconciliation rule gains the still-deferred outcome and the deferred-recurrence rule — verify by diffing the prompt text and by a scratch run where the judge's output must reconcile a deferred id

## 5. Documentation

- [ ] 5.1 Update `playbooks/pr/README.md`: the Escalate section and the trigger description state the open-blocking gating, the persisted `needsHuman` field, and the deferred-recurrence reconciliation — verify the README's loop description matches the spec delta
- [ ] 5.2 Add the coordination note to the change or README (whichever the repo convention favors) that the ptah repository's offline suite owns coverage for the gated trigger and the deferred reconciliation value — verify `openspec validate escalate-only-blocking` and `ptah check` both pass

## 6. Wrap-up

- [ ] 6.1 Run `ptah check` on the library and `openspec validate --strict` on the change, then confirm the delta's new scenarios (non-blocking `needsHuman` does not ask; unknown reconciliation id never escalates; deferred recurrence reconciles by id; flag persists and updates; legacy ledgers read tolerantly) each have corresponding behavior in the code
