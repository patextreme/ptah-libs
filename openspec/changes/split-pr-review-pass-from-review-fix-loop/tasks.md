# Tasks

## 1. Facade split in `playbooks/pr/playbook.luau`

- [x] 1.1 Extract the review-pass primitive (prompt with `[pr-review pass]` header → work session → judge → `applyFindings` → persist → returns verdict) as a closure in `M.new` shared by both operations; verify the loop's sequence still runs identically through it
- [x] 1.2 Rename the existing loop operation to `reviewFixLoop` (Instance type + implementation), keeping its resume fast paths, fix turns, budget rule, and never-ask behavior byte-stable; verify by diffing behavior against the prior tag's `review`
- [x] 1.3 Implement `review` as one unconditional call to the pass primitive — discovery when no ledger, delta otherwise, no fast path, never fixes — returning the shared `Outcome` with `verdict` = pass prose and status from open blocking count; verify a dry call against a mocked ledger leaves no fix prompt in the transcript
- [x] 1.4 Add pass session ids in the `pr-review` family (`pr-review-pass`, `pr-review-pass-judge`); verify markers, error prefixes, and existing ids are unchanged (`git grep "ptah:pr-review"` and prefix greps)

## 2. Report contract

- [x] 2.1 Rename the summary section to "Review summary" in `sectionContract` and carry a pass count (1 for `review`; loop units for `reviewFixLoop`) through `buildReporterPrompt`; verify the loop's report differs only in that section
- [x] 2.2 Verify `review` always prompts the reporter with prose (no no-prose marker) and `reviewFixLoop` keeps the marker on resume fast paths

## 3. Documentation

- [x] 3.1 Update `playbooks/pr/README.md`: two operations, pass semantics (unconditional, never fixes), config knobs marked loop-only, pointer to ADR 0006, and a migration note leading with the silent-shrink warning (`:review` → `:reviewFixLoop` for loops; pin prior tag)
- [x] 3.2 Update the library `README.md` and `playbooks/README.md` operation tables/facade lists; verify every `:review(` reference now names the right verb
- [x] 3.3 Verify the playbook documentation states "one operation per PR at a time" (replacing "one loop per PR") and keeps the ledger/report/`gh` environment requirements

## 4. Spec sync and validation

- [x] 4.1 Run `openspec validate --change "split-pr-review-pass-from-review-fix-loop" --strict` and fix any reported issues
- [x] 4.2 Verify the delta against the main spec: removed "PR review loop playbook", added "PR review pass" + "PR review-fix loop", modified report/ledger/instruction-contract requirements, and no stale `review`-operation references left in `openspec/specs/playbooks/spec.md` after a mental sync (grep for "fresh `review` operation")
- [x] 4.3 Note in the change that the ptah repo's offline suite owns updated coverage (new pass entry point; consolidated ask-retirement pins) — no test files exist in this repo

> **Coverage ownership.** This repo ships no test files. The ptah
> repository's offline suite owns updated coverage for this change: the new
> pass entry point (`review` as one unconditional, never-fixing pass), the
> loop's byte-stable sequence through the shared pass primitive, and the
> consolidated ask-retirement pins (the removed requirement's six
> ask-retirement pins collapse into two scenarios carrying the same
> normative content — the behavioral pins live in the offline suite).

## 5. Delivery

- [ ] 5.1 Commit the change artifacts plus the already-staged `CONTEXT.md` glossary entries and `docs/adr/0006-review-pass-vs-review-fix-loop.md` on `issue-34`; verify `git status` is clean
- [ ] 5.2 Push `issue-34` to `origin` and confirm the branch tracks; reference issue #34 in the commit message
