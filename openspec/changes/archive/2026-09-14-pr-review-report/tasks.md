## 1. Config and outcome surface

- [x] 1.1 Add the required `reporterAgent: Agent` handle and optional `reporterSessionConfig: { sessionConfig.Entry }?` to `Config`, with doc comments stating the reporter authors the report and the playbook posts it; verify the module still type-checks under the project's Luau analyzer
- [x] 1.2 Add `report: string` (the posted report text) to `Outcome` and to every `Outcome` return site in `playbook.luau`; verify the analyzer accepts the new field and a shim can read `outcome.report`

## 2. Ledger retention of resolved findings

- [x] 2.1 Change `applyFindings` so a finding the judge reconciled as resolved is retained with `status = "fixed"` instead of dropped, while `resolvedCount` still increments; ensure `fixed` entries are skipped by reconciliation, `hasOpenBlocking`, and the open-findings summary; verify by tracing a run with one resolved blocking finding that the ledger holds a `fixed` entry and the count advanced

## 3. Reporter session, schema, and prompt

- [x] 3.1 Add the report `resultSchema` (`{ report: string }`, required, no additional properties) and a `runReporter` that creates a reporter session, applies `reporterSessionConfig` in declared order, and bounded-retries a missing typed result, raising on exhaustion with an error naming the reporter and the attempt count; verify a scripted no-typed-result path raises
- [x] 3.2 Add a full-ledger renderer (findings grouped by status including retained `fixed` entries, intention, families, discovery/last-reviewed SHAs, resolved count) and assemble the reporter prompt from it plus the terminal status, the last review pass's prose when the operation ran one (`string?`, rendered as an explicit no-prose marker when nil), and the required section contract (*What this PR does*, *Findings resolved*, *Open non-blocking*, *Deferred*, *Accepted*, *Loop summary*, plus *Open blocking* for a non-converged outcome); the section contract SHALL cap the *Findings resolved* list at the 50 most recent entries with an "…and N earlier omitted" note (the ledger retains every entry, and the renderer still supplies every status group); verify the assembled prompt contains every section, every finding status group both with prose and with the no-prose marker, and the resolved-cap rule, and that a ledger with more than 50 `fixed` entries yields a prompt carrying the cap rule

## 4. Report transport and status line

- [x] 4.1 Add report-comment read/create/update through `std/gh` under the marker `<!-- ptah:pr-review-report -->`, editing in place across runs and mirroring the ledger helpers; verify two runs against one PR leave a single report comment (edit, not append)
- [x] 4.2 Compose the deterministic status line from the outcome status and the open blocking count (read from the ledger) and prepend it to the reporter body; verify the converged and capped status lines differ, the counts match the ledger, and `outcome.report` equals the posted text

## 5. Wire the terminal outcomes

- [x] 5.1 Replace `buildVerdictPrompt` and the posting half of `converge()` with a single report step that every `Outcome` return routes through (the in-loop converge, the fast resume converge, the resume-at-cap return, the in-loop cap return, and the loop-exhaustion return) — after the ledger is persisted, with the review session closed first; verify every returning terminal path calls the report step exactly once and no work session posts a comment
- [x] 5.2 Remove the `pr-review:converge` fast-path work session while keeping the clean-ledger-at-current-head detection, so that path goes straight to the reporter; verify no work session is created on the fast path

## 6. Documentation and consumer surface

- [x] 6.1 Rewrite the README's converge phase as the PR review report, state terminal-outcome coverage (converged and capped; aborted asks raise), document the config surface (`reporterAgent`, `reporterSessionConfig`) and `outcome.report`, and add migration notes; verify the README contains no remaining "verdict comment" and names the report
- [x] 6.2 Add the **PR review report** term to `CONTEXT.md` and retire the verdict-comment wording; verify the glossary entry exists and the old term is gone

## 7. Validation

- [x] 7.1 Run `openspec validate pr-review-report --strict` and confirm every artifact (proposal, specs, design, tasks) validates
- [x] 7.2 Type-check the library and the adhoc workflow with the project's Luau analyzer and confirm no errors remain
