## 1. openspec playbook: the bar in copy

- [ ] 1.1 Reword the three `probePrompt` strings (groom, implement, verify) to instruct self-resolution with the operator-owned-decision exception, and the three `humanPredicate` strings to the authority bar ("requires an operator-owned decision … a confirmation or mechanical choice does not count") in `playbooks/openspec/playbook.luau` — verify by diffing the per-operation data against design.md's final strings and `ptah check`
- [ ] 1.2 Append the component-owned autonomy clause ("make judgment calls autonomously, note each in your output as 'judgment call: …', the loop re-judges every pass, never wait for confirmation") to every work prompt once, in `drive()`'s prompt composition — verify with `ptah check` and a scratch single-iteration run whose header+prompt carries the clause

## 2. pr playbook: retire the ask

- [ ] 2.1 Delete the ask machinery in `playbooks/pr/playbook.luau`: the ask call and its payload composition (answer grammar, triggering-findings naming), `runAdjudication` and its schema and `DEFAULT_ADJUDICATION_ATTEMPTS`, the decisions-record writer, and both ask-failure error paths; reduce `triggeringFindings` to nothing (delete it) — verify with `ptah check` (no unused symbols) and that no `escalate` require remains in the pr playbook
- [ ] 2.2 Reword the judge rule in `buildJudgePrompt`: `needsHuman` is set only on an open blocking finding resting on an operator-owned decision a human should examine at review; keep the never-on-deferred-or-non-blocking sentence verbatim — verify by diffing the Rules block
- [ ] 2.3 Make the decisions record and `accepted` status legacy-only: tolerate them on ledger read (already tolerant), never write them; confirm the resume fast path's `hasOpenBlocking` fix turn treats flagged findings like any other (no code change expected — verify by reading, and reference the "Resume auto-fixes flagged findings" scenario) — verify with `ptah check` and by hand-loading a legacy ledger JSON (decisions + one accepted finding) through `readLedger` in a scratch `ptah run` script: it parses, decisions ignored, accepted stays terminal, re-persist omits decisions

## 3. Documentation

- [ ] 3.1 Update `playbooks/pr/README.md`: remove the Escalate section's ask/answer-grammar/adjudication/decisions-record description and state the report-only `needsHuman` semantics (auto-fix, report pointer, PR as the human checkpoint); update `judgeSessionConfig` docs to drop the adjudication mention — verify the README's loop description matches the spec delta
- [ ] 3.2 Update `playbooks/openspec/README.md`: the probe's authority bar and the autonomy clause — verify the README matches the reworded strings
- [ ] 3.3 Confirm `CONTEXT.md` (Escalation rewrite, Operator-owned decision, Recoverable choice) and `docs/adr/0005-*` are on the branch and consistent with the implemented behavior — verify by reading both against the final prompt strings

## 4. Verification

- [ ] 4.1 Run `openspec validate escalate-operator-owned-only --strict` and `ptah check` — both pass
- [ ] 4.2 Scratch-run the pr loop against a fixture PR whose judge output flags `needsHuman` on an open blocking finding (dry-run): the loop issues the fix turn with no ask, the ledger persists the flag, and the rendered report shows ", needs human" on the finding's line — verify by inspecting the run log and the dry-run report text
- [ ] 4.3 Add the coordination note that the ptah repository's offline suite owns updated coverage for the retired ask path (no ask is raised; flagged findings drive fix turns) and the openspec probe's confirmation-never-escalates predicate — verify with the note in the change's wrap-up and `openspec list` showing the change ready for archive
