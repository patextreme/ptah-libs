# Tasks — convergent pr-review-loop

## 1. Types and protocol fragment

- [ ] 1.1 Define the ledger type (`Ledger`: pr identity, discoverySha, lastReviewedSha, intention, findings with id/family/severity/validation/status/fixCommit, families, resolvedCount) and the judge findings type (`Findings`: findings with severity/family/validation/needsHuman, priorFindingsStatus reconciliation) in `playbook.luau`; verify with `ptah check` in a consumer-shaped shim
- [ ] 1.2 Create the protocol fragment module (`protocol.luau` or equivalent): component-owned instruction text carrying delta-review rules, report-recurrences-by-ledger-id, family reuse-or-justify guidance; verify it is a data-only module (no config, no runtime handles) with `ptah check`

## 2. Ledger via std/gh

- [ ] 2.1 Implement ledger read: list PR comments via `std/gh`, locate the `<!-- ptah:pr-review-ledger -->` marker, parse the JSON block; verify against a mocked `gh` outcome
- [ ] 2.2 Implement ledger create/update-in-place (PATCH the existing comment, never append a new one); verify update targets the original comment id in a mocked run
- [ ] 2.3 Implement compaction: collapse findings verified clean in a later pass to a resolved count; verify the ledger JSON shrinks and `resolvedCount` increments
- [ ] 2.4 Implement intention capture at discovery: PR title/body via `std/gh`; fallback to the last commit message before the first ledger record when the body is absent; verify both branches

## 3. Judge as schema boundary

- [ ] 3.1 Implement the judge session: created with the findings `resultSchema`, receiving review prose + ledger + intention + `blockingAdditions`; returns typed findings; verify typed parse from a mock agent result
- [ ] 3.2 Implement judge retries (bounded attempts in the `std/predicate` pattern) with exhaustion failing the iteration; verify exhaustion raises and no fix prompt is issued
- [ ] 3.3 Wire `judgeSessionConfig` onto every judge session and verify entries apply in declared order before the judge prompt

## 4. Phase machine and loop rewrite

- [ ] 4.1 Rewrite `playbook.luau` around the phase shape: discovery pass (full-PR review) for a ledger-less PR; auto-resume from an existing ledger (open blocking → fix turn; clean at head → converge); verify both entry paths
- [ ] 4.2 Implement delta review: verify prompts carry `lastReviewedSha` and the ledger data (open findings, family names), and `lastReviewedSha` advances after each pass; verify the prompt contains the SHA and the ledger summary
- [ ] 4.3 Implement convergence from the judge's typed output (`openBlocking == 0`) with the converged work session posting the verdict comment including the deferred list; verify the comment prompt includes deferred findings
- [ ] 4.4 Implement deferral: judge-deferred findings get ledger status `deferred`, do not gate convergence; verify convergence succeeds with a deferred finding open
- [ ] 4.5 Implement the single cap: fix+push only when open blocking findings exist and budget remains; at the cap with open findings return a non-converged outcome without a fix; verify no fix prompt is issued on the final unit
- [ ] 4.6 Implement the batched fix turn (all open blocking findings, by root cause) followed by commit-and-push gated by `dryRun`; verify dry-run skips the push prompt
- [ ] 4.7 Implement prompt assembly: persona (`reviewInstruction` or default) + protocol fragment + phase directive + ledger data, with the protocol always appended for both configured and default personas; verify a configured persona does not remove the protocol fragment

## 5. Escalation

- [ ] 5.1 Wire the judge's `needsHuman` flag to `std/escalate`: ask shape (loop, PR URL, iteration state; details carry work-session label and full review prose); answered ask sends the text verbatim into the still-open work session, iteration counts against the cap; verify with a mocked ask provider
- [ ] 5.2 Preserve abort and unavailable semantics: distinct "human aborted" error and the pre-ask "human input is required" error wording; verify both paths and that no fix is issued

## 6. Config surface and outcome

- [ ] 6.1 Update the exported `Config` type: `agent`, required `judgeAgent`, `sessionConfig`, `judgeSessionConfig`, `reviewInstruction` (persona; nil selects default), `blockingAdditions`, `dryRun`, `maxIterations` (default 8); nil-typed `model`/`judgeModel` retained so configuration is a check error; verify with `ptah check` against a consumer shim
- [ ] 6.2 Change `review` to return the typed outcome (status, verdict text, ledger snapshot); verify the outcome is populated on converged, non-converged, and answered-ask paths

## 7. Default instruction

- [ ] 7.1 Rewrite `default-instruction.luau`: drop the blocking/non-blocking classification directive, preserve the persona content otherwise; verify the classification vocabulary no longer appears as a reviewer duty and `ptah check` passes

## 8. Documentation

- [ ] 8.1 Rewrite `README.md` intro and operations: phase shape, typed judge, ledger (auto-resume, compaction, playbook-owned, one-loop-per-PR), typed return outcome; verify the documented behavior matches the spec deltas
- [ ] 8.2 Rewrite the contract section to the three layers (persona full replacement, protocol appended and not configurable away, taxonomy owned by judge + `blockingAdditions`) and update the config doc comments (`reviewInstruction`, `blockingAdditions`) to state each field's layer; verify against the Config type
- [ ] 8.3 Document environment requirements and boundaries: `gh`-based PR host, subagent-capable work agent, one loop per PR, no CI/gate reading (caller's script), migration notes for the identus-ws-lineage consumer (`maxIterations` default change, required judge, new outcome return); verify the migration notes cover every breaking item in the proposal

## 9. Verification

- [ ] 9.1 Add/extend offline coverage in the ptah repository: phase machine, judge retries and exhaustion, ledger create/read/update/compaction against mocked `gh`, cap semantics (no fix on the last unit), escalation paths, dry-run; verify the offline suite passes with no network and no real agent
- [ ] 9.2 Run `openspec validate` on the change and confirm all artifacts complete; verify the spec deltas and tasks are consistent with the implementation