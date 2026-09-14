## 1. std helpers

- [ ] 1.1 Add `std/shell.luau` exporting `trim`, `quote`, `mustRun`, `succeeds`, and `errorMessage` (see design D9). Verify with a scratch shim that `quote` passes a value containing spaces and a single quote verbatim, `mustRun` raises carrying exit code and stderr on failure, and `succeeds` returns false without raising.
- [ ] 1.2 Re-route `std/gh.luau` and `std/daemon.luau` through `std/shell` and delete their private copies. Verify `std.gh.run` still returns the same structured outcome for success, failure, and requested JSON, with a value containing a quote in an argument.
- [ ] 1.3 Add `std/agent.luau` with `inDirectory(agent, dir)` returning a structural agent handle whose sessions always receive `dir`, overriding any call-site `cwd` (design D4). Verify every session created through the wrapped handle sees the wrapped directory, both with and without an explicit `cwd`.
- [ ] 1.4 Add `std.agent` and `std.shell` to the `std` table in `lib.luau`. Verify a shim requiring the package entry reaches both.

## 2. ciGate playbook

- [ ] 2.1 Add `playbooks/ci-gate/playbook.luau` with `new(config)` accepting `agent`, `sessionConfig`, `timeoutSeconds`, `pollSeconds`, and `repairAttempts`, and a `watch(prUrl)` operation (design D1/D6). Verify the Config type rejects a missing `agent` and a callable value under `ptah check` on a shim.
- [ ] 2.2 Implement rollup classification across check-run `conclusion`/`status` and status-context `state`, returning `green` only when every entry is successful, neutral, or skipped. Verify mixed rollups: pending entries classify as pending, never failing.
- [ ] 2.3 Implement the bounded repair loop (agent session prompted with the failing logs, signed repair push) and the typed outcomes `{ status = "green" | "unresolved", attempts, reason? }` with no raise on exhaustion or timeout, and no ask. Verify green, budget-exhausted, and wait-timeout paths each return the right outcome.
- [ ] 2.4 Add `playbooks/ci-gate/README.md` declaring environment requirements (`gh` with check access, an agent able to push signed repairs) and the outcome-as-data boundary. Verify the requirements are listed.

## 3. issueWorker meta playbook

- [ ] 3.1 Add `playbooks/issue-worker/git.luau` — private git mechanics: repo root discovery, worktree create-or-reuse on the issue branch from `origin/<baseBranch>`, and commits-ahead count (design D1). Verify create, reuse-after-crash, and branch-mismatch failure against a scratch repository.
- [ ] 3.2 Add `playbooks/issue-worker/playbook.luau` with the exported `Config` type (role handles, three session-config arrays, required labels/base branch/branch prefix/gate commands, defaulted caps and `repoBrief`, openspec opt-in) and the `run` / `pickup` / `process` operations returning the discriminated outcome (design D5/D6). Verify a shim with a valid config type-checks and one missing a required field fails `ptah check` naming it.
- [ ] 3.3 Implement pickup: ensure labels idempotently, list open issues carrying the ready label oldest-first, skip assigned / open-PR / branch-without-worktree, claim by assigning the authenticated user, and skip on a lost claim (design D2). Verify each skip rule and the oldest-first claim.
- [ ] 3.4 Implement triage: typed verdict schema (route, rationale, commit type, change name), bounded retry, the `direct` / `reject` routes, the `openspec` route only when opt-in is set, and the change-directory guard before driving the openspec playbook. Verify an invalid verdict is retried, an openspec verdict without its change fails, and openspec-off offers only the two routes.
- [ ] 3.5 Implement direct-route implementation and the delivery contract: run `gateCommands`, merge (never rebase) the base branch, push, open the PR with the composed title and closing reference, then deterministically re-check commits-ahead, URL shape, and title (correct-or-fail). Verify ahead=0 fails, a wrong title is corrected, and the branch is merged rather than rebased.
- [ ] 3.6 Implement bookkeeping: success comment with the PR URL leaving label and claim; rejection/failure comment with the reason, ready→blocked label swap, and claim release (design D5). Verify the two paths on a scratch repository.
- [ ] 3.7 Wire the nested playbooks — openspec (when enabled), `prReviewLoop`, and `ciGate` — driving them with the per-issue handle wrapped once via `std.agent.inDirectory`, so no stage sets `cwd` and every session runs in the worktree (design D4). Verify every session in a run receives the worktree directory.
- [ ] 3.8 Add `playbooks/issue-worker/README.md` declaring environment requirements: the agent registry handle(s), `gh` rights (label, assign, comment, create PR), `git` with commit signing for the configured `commitSignArgs`, `openspec` on PATH only when the route is enabled, and that the consumer must gitignore `worktreeDir`. Verify the requirements are listed.

## 4. Exports and vocabulary

- [ ] 4.1 Add `issueWorker` and `ciGate` to the entry in `lib.luau`. Verify a shim requiring the package entry reaches both, and the existing exports are unchanged.
- [ ] 4.2 Add the glossary term **Meta playbook** to `CONTEXT.md` (a playbook that *composes* std, other playbooks, and deterministic stages over a whole unit of work), and adjust the `Playbook` entry so the two do not collide. Verify no term is defined twice and the `_Avoid_` lists stay consistent.
- [ ] 4.3 Update `README.md`'s Exports table and Layout section for `std.agent`, `std.shell`, `issueWorker`, and `ciGate`. Verify every exported key is documented and no removed key remains.

## 5. Lace migration

- [ ] 5.1 On `input-output-hk/lace-id-portal` branch `issue-worker`, replace `.ptah/workflows/issue-worker/` with a shim `main.luau` that requires the package, constructs the handles, passes the Local config (`readyLabel = "ai-r4d"`, `blockedLabel = "ai-blocked"`, base branch, branch prefix, gate commands, signing args, `repoBrief`), calls `run`, and maps the outcome to an exit code; delete the ten modules. Verify no remaining file in the repo requires them.
- [ ] 5.2 Re-lock the pesde dependency (`rev = "main"`; design D8) and commit `.ptah/pesde.toml` / `.ptah/pesde.lock`. Verify `ptah package install --locked` succeeds from a clean checkout of the branch.
- [ ] 5.3 Run `ptah check .ptah/workflows/issue-worker/main.luau` from the lace repo root. Verify it reports no findings other than the known generated-shim strict-directive one documented in the library README.
- [ ] 5.4 Update the lace workflow README for the new shape and the `worktreeDir` gitignore / environment requirements. Verify the documented run command matches the shim path.

## 6. Verification

- [ ] 6.1 Run `openspec validate extract-issue-worker --strict` and fix every finding. Verify it exits clean.
- [ ] 6.2 Re-read the delta spec against the implementation surface and confirm every requirement has at least one satisfied scenario, with no scenario that the design contradicts. Verify by walking the spec's requirement list against `lib.luau` and the two new playbook directories.
- [ ] 6.3 Record the deferred follow-up (upstream ptah offline coverage for the new std modules and playbooks, plus the stale README "no suite yet" correction) as a separate change, and confirm this change cuts no tag. Verify the follow-up is captured and the decision is stated in `design.md`'s non-goals.
