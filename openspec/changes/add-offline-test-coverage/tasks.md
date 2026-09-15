## 1. Upstream offline coverage

- [ ] 1.1 Add ptah mock-agent cases for `std/shell.luau`: `quote` round-trips a value containing spaces and a single quote, `mustRun` raises carrying the exit code and stderr, `succeeds` returns false without raising, and `errorMessage` normalizes a caught non-string.
- [ ] 1.2 Add coverage that `std/gh.luau` and `std/daemon.luau` route through `std/shell` (structured outcome for success/failure/JSON; per-repo error isolation).
- [ ] 1.3 Add mock-agent coverage for `std/agent.luau`: every session created through `inDirectory(agent, dir)` receives `dir`, with and without a call-site `cwd`, and the caller's options are not mutated.
- [ ] 1.4 Add mock-agent coverage for the `ciGate` playbook: green, budget-exhausted, and wait-timeout outcomes; mixed rollups classify pending entries as pending and failing status contexts as failing; a repair prompt carries the configured `commitSignArgs`.
- [ ] 1.5 Add mock-agent coverage for the `issueWorker` meta playbook: pickup skip rules and oldest-first claim, the three triage routes and the invalid-verdict retry, the delivery deterministic re-checks (commits-ahead, URL shape, title correct-or-fail), success/rejection/failure bookkeeping, and the typed outcome mapping; assert every session in a run receives the worktree directory.

## 2. Documentation correction

- [ ] 2.1 Correct `README.md`'s Versioning section: replace the "no suite yet / no tag" note with the real state of the ptah mock-agent suite and what it covers, and confirm the statement is consistent with the *Offline test coverage* requirement.

## 3. Verification

- [ ] 3.1 Run the upstream offline suite and confirm every new case passes without a network or a real agent.
- [ ] 3.2 Run `openspec validate add-offline-test-coverage --strict` and fix every finding.
