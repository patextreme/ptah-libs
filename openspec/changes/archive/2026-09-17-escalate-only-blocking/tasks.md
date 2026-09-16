## 1. Ledger schema and persistence

- [x] 1.1 Add `needsHuman: boolean` to `LedgerFinding` and a `decisions` array to `Ledger` in `playbooks/pr/playbook.luau`; copy the flag in `applyFindings` on insertion and update it when a reconciliation record revisits the finding — verify with `ptah check` and by reading the persisted ledger JSON of a scratch run
- [x] 1.2 Make ledger reading tolerant of both fields' absence (legacy ledgers parse as `needsHuman = false`, no decisions) and always write them on persist — verify by hand-loading a pre-change ledger JSON (e.g. PR #14's) through `readLedger` in a scratch `ptah run` script and checking the re-persisted comment carries the fields

## 2. Gated escalation predicate

- [x] 2.1 Rename `anyNeedsHuman` to a gating name (e.g. `anyBlockingNeedsHuman`), filter new findings on `status == "open" and severity == "blocking" and needsHuman`, and join reconciliation records by id against `ledger.findings` (open + blocking only; unknown ids never escalate) — verify with `ptah check` and a scratch judge fixture run whose typed output flags `needsHuman` on a deferred finding only: no ask is raised
- [x] 2.2 Render the persisted flag in `renderFinding` (append `, needs human` when true on undecided findings) — verify by inspecting a scratch run's posted report text

## 3. Deferred dedup

- [x] 3.1 Extend `ledgerSummary` with a deferred-findings section (id, severity, family, title) so the judge sees deferred ids alongside open ones — verify the judge prompt text of a scratch run lists a deferred finding by id
- [x] 3.2 Add `"deferred"` to the reconciliation status enum in `JudgeReconciliation` and `FINDINGS_SCHEMA`, and handle it in `applyFindings` as a no-op confirmation (no duplicate entry; `needsHuman` still updates per task 1.1) — verify a scratch run whose judge reports a deferred recurrence against the existing id creates no new ledger entry

## 4. Adjudication pass

- [x] 4.1 Define the adjudication result schema (per-finding mutations: `defer`/`accept`/`fix` with optional note) and the `runAdjudication` session helper on the judge agent (`pr-review-adjudicate:{iteration}` id, `judgeSessionConfig`, bounded retry with exhaustion failing the iteration) — verify with `ptah check` and a scratch adjudication fixture returning malformed output (retry fires) and valid output (mutations returned)
- [x] 4.2 Apply adjudication mutations in `applyFindings` or a sibling writer: `defer` → open→deferred, `accept` → open→accepted (decision note retained), `fix` → stays open; unknown or terminal ids are no-ops; the decided finding's `needsHuman` flag clears — verify a scratch run transitions a fixture finding per mutation and clears its flag
- [x] 4.3 Rewire the respond branch: adjudicate first; when at least one `fix` mutation exists, send the answer verbatim to the still-open work session followed by commit-and-push (dry-run gated); on decision-only answers, issue no session prompt and no push; close the session and count the unit either way — verify a decision-only fixture run performs no `git` push and no work-session prompt (log/prompt trail), and a `fix` fixture run does both

## 5. Decisions record and immediate convergence

- [x] 5.1 Record each answered ask in the ledger's `decisions` array (prompt line, verbatim answer, applied mutations with notes, in ask order) — verify the persisted ledger comment of a scratch ask/answer cycle carries the entry
- [x] 5.2 After a decision-only adjudication leaves no open blocking findings, converge immediately without a further review pass (mirror the resume-path immediate converge) — verify a scratch run with a single deferred-by-decision blocker ends converged with no empty-delta review pass in the log

## 6. Ask payload

- [x] 6.1 Build the ask prompt line to name every triggering finding (id, family, severity, title) and prefix the details with the answer grammar (`defer <id>`, `accept <id>`, `fix: <instructions>`) before the session label, ACP session id, and full review prose — verify the ask payload text of a scratch run with two triggering findings names both and carries the grammar untruncated

## 7. Judge prompt rules

- [x] 7.1 Edit the Rules block in `buildJudgePrompt`: `needsHuman` meaningful only on open blocking findings (never on deferred or non-blocking; human-worthy non-blocking concerns go in the prose), the reconciliation rule gains the still-deferred outcome and the deferred-recurrence rule — verify by diffing the prompt text and by a scratch run where the judge's output must reconcile a deferred id

## 8. Documentation

- [x] 8.1 Update `playbooks/pr/README.md`: the Escalate section (gated trigger, named findings, answer grammar, adjudication path, decisions record, conditional push), the persisted `needsHuman` field, and the deferred-recurrence reconciliation — verify the README's loop description matches the spec delta
- [x] 8.2 Add the coordination note that the ptah repository's offline suite owns coverage for the gated trigger, the deferred reconciliation value, and the adjudication mutations — verify `openspec validate escalate-only-blocking` and `ptah check` both pass

## 9. Wrap-up

- [x] 9.1 Run `ptah check` on the library and `openspec validate --strict` on the change, then confirm the delta's scenarios each have corresponding behavior in the code: non-blocking `needsHuman` does not ask; unknown reconciliation id never escalates; deferred recurrence reconciles by id; flag persists, updates, and clears; legacy ledgers read tolerantly; the ask names findings and grammar; the answer is adjudicated before any fix turn; a decision reaches the ledger; a `fix` answer drives a human-guided fix turn; a decision-only adjudication converges immediately; mutations are inert on unknown or terminal ids; adjudication exhaustion fails the iteration
