# Tasks

## 1. Spike — the atomic check read

- [ ] 1.1 Run the design's D3 GraphQL query live through `gh api graphql` against a PR with checks (including required ones, e.g. the evidence PR's repo or a public equivalent); pin the exact node spellings (`CheckRun.name/status/conclusion/detailsUrl` + `isRequired(pullNumber:)`, `StatusContext.context/state/targetUrl`), the pagination shape, and how `detailsUrl` maps to a failing run URL — verify by capturing the query and its parsed output into the implementation notes; if required-ness is unreadable, surface it now (design D3 forbids silent scope drift under `"required"`)
- [ ] 1.2 Add the check read as a playbook-local transport helper (head SHA + classified rollup + required-ness in one call; green/red/pending per design D4, empty in-scope set vacuously green) — verify with `ptah check` and a scratch `ptah run` script printing the classified snapshot for a real PR, including a truncation log when the rollup exceeds the page cap

## 2. Ledger — check findings

- [ ] 2.1 Add `source` and `check` to `LedgerFinding`; write them from the check-gate writer; read tolerantly (absent `source` → `"review"`, absent `check` → nil) and always persist them — verify by hand-loading a pre-change ledger JSON through the parse path in a scratch `ptah run` script and checking the re-persisted comment carries the fields
- [ ] 2.2 Exclude check findings from `ledgerSummary` (the judge's ledger view) and treat reconciliation records naming a check finding as inert in `applyFindings` — verify with a scratch run whose ledger holds a check finding: the judge prompt's summary omits it and a fixture reconciliation naming its id leaves it untouched
- [ ] 2.3 Render check findings in `renderFinding`/`renderLedger` so they appear in the open blocking groups with their check name and run URL, and receive fixing commits from `recordFixCommit` like any open blocker — verify by inspecting a scratch run's posted report text and persisted ledger

## 3. Check gate machinery

- [ ] 3.1 Implement `reconcileChecks`: green-at-head closes every open check finding (`fixed`, resolved count advanced), red updates-or-files one finding per failing check name (blocking, `needsHuman` false, family `"check"`, validation `"validated"`, title carrying check name + failing run URL), pending files nothing — verify with a scratch run feeding fixture snapshots (green after red closes; red-while-open updates in place; re-failure after green files a new id)
- [ ] 3.2 Implement the two consult flavors: snapshot (single read + `reconcileChecks`) and gate (read; if pending and review-clean, poll `ceil(pollBudgetMs / pollIntervalMs)` iterations with `ptah.sleep`, breaking on green/red) — verify with `ptah check` and a scratch run against a PR with pending checks shortened to a small budget: the poll log shows bounded iterations and a named pending result
- [ ] 3.3 Validate the `checks` config at `M.new` (scope enum; positive non-zero budget and interval; interval ≤ budget) — verify misconfigurations (`scope = "some"`, zero budget) fail at construction with errors naming the field

## 4. Loop wiring

- [ ] 4.1 Mid-loop convergence exit: when the pass is judge-clean and the gate is on, run the gate consult before `finish` — green converges, red files findings and falls through to the existing fix-turn/cap logic, pending at budget ends non-converged named — verify with a scratch run whose judge fixture is clean and whose PR carries a red check: the loop issues a fix turn and the next pass's consult converges on green
- [ ] 4.2 Resume fast path, restructured: clean-at-head consults the gate first (green converges with no session; red files and issues the fix turn directly); open-blockers performs the snapshot consult (no wait) so the fix turn batches check findings — verify with scratch resumes of (a) a clean ledger on a green PR (converges, no session), (b) a clean ledger on a red PR (files, fixes), (c) a blocker ledger with a red check (the fix prompt lists both findings)
- [ ] 4.3 Confirm the cap interplay: on the final unit a judge-clean pass with a red check ends non-converged with the finding open, and no fix is issued without a following pass — verify with `maxIterations = 1` on a PR with a red check: the run ends non-converged, the report leads with the check finding

## 5. Outcome and report

- [ ] 5.1 Add `ChecksSnapshot` and the `checks` field on `Outcome` (always from `reviewFixLoop`, nil from `review`); fill `off` when ungated — verify with `ptah check` and scratch runs of both operations
- [ ] 5.2 Extend `statusLine` with the checks clause when the gate is configured (`; checks green` / `; checks red: …` / `; checks pending: …` / `; checks unknown`), byte-identical when off; keep the reporter's section contract unchanged — verify by diffing posted report text from gated and ungated scratch runs against today's format
- [ ] 5.3 Terminal snapshot read: one non-waiting consult at every terminal outcome, two bounded retries on transport failure, then degrade to `state = "unknown"` with a `ptah.log` — verify with a scratch run whose final read is forced to fail (bad `GH_HOST`): the outcome carries `unknown`, the report posts, and the log names the degradation

## 6. Config default and documentation

- [ ] 6.1 Move the `maxIterations` default 8 → 10 with a migration note (consumers wanting the old cap set it explicitly) — verify with `ptah check` and by reading the constructed default in a scratch script
- [ ] 6.2 Rewrite the README's environment-requirements boundary section (platform check state in when gated; repo gate commands out), and document the `checks` config, the per-consult budget arithmetic (`maxIterations × pollBudgetMs` worst case), the dry-run interaction, the vacuous-required stance, and `checks` as loop-only — verify the README matches the spec delta's requirements and design D2/D6/D9
- [ ] 6.3 Add the glossary entries (check, check finding, check gate, repo gate commands) and the review-fix-loop sharpening to `CONTEXT.md` — verify against ADR 0008's vocabulary and the delta's terms

## 7. Wrap-up

- [ ] 7.1 Run `ptah check` on the library and `openspec validate gate-review-loop-convergence-on-checks --strict`; then walk the delta's scenarios against the code: gate off unchanged; red cannot end converged; fix-turn regression picked up; resume consults; pending named; STALE pending; vacuous green; never re-filed; judge-blind; report/outcome carry state; pointer not diagnosis; shared budget; dry-run honesty — confirm each has corresponding behavior before archiving
