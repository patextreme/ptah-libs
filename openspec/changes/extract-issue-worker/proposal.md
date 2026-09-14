## Why

`input-output-hk/lace-id-portal` has built an unmerged, ~800-line
`issue-worker` workflow (`.ptah/workflows/issue-worker/`, 10 modules) that
drives one GitHub issue end-to-end: pickup → triage → implement → PR →
review → CI. It composes the library's own `openspec` and `prReviewLoop`
playbooks plus deterministic git/`gh` steps, but every bit of it — including
generic mechanics like worktree setup, cwd pinning, and shell quoting — lives
in the consumer repo. A sibling (`input-output-hk/identus-workspace`) already
hand-rolls its own `ci.luau`, and any repo wanting the same flow must fork the
whole thing. The library's contract is exactly "compose and configure rather
than fork" (`CONTEXT.md`), and issue-worker is the strongest demonstration of
it — so it belongs in the library, not in one consumer's branch.

## What Changes

- Add a new **`issueWorker` meta playbook**: the full one-issue lifecycle as
  typed operations (`run()`, `pickup()`, `process(issue)`), returning a typed
  outcome (`delivered` / `rejected` / `idle` / `failed`). The playbook owns
  the deterministic mechanics (worktree/branch invariants, delivery re-checks,
  label lifecycle, bookkeeping) and never calls `ptah.agent`, `ptah.ask`, or
  `ptah.exit` literally, so it is safe to require from any consumer.
- Add a new **`ciGate` playbook**: watch a PR's check rollup to completion and
  hand failing logs to an agent for a bounded number of repair pushes,
  returning a typed outcome (`green` / `unresolved`) instead of raising. This
  is a separate capability because the pr-review-loop spec explicitly places
  CI outside that playbook, and a second consumer already duplicates it.
- Add **`std.agent.inDirectory(agent, dir)`** — wrap an agent handle so every
  session it creates is pinned to `dir` (force-cwd). This is the missing seam
  that lets a playbook run nested playbooks (which accept no `cwd`) inside a
  per-issue worktree, and it replaces lace's ad-hoc proxy.
- Add **`std.shell`** — `trim`, `quote`, `mustRun`, `succeeds`,
  `errorMessage` — and route `std.gh` and `std.daemon` through it, removing
  three private copies of the same helpers.
- Add the new exports to the package entry: `std.agent`, `std.shell`,
  `issueWorker`, `ciGate`.
- **Config becomes data**: `readyLabel`/`blockedLabel` (required — the library
  bakes no repo's label), `baseBranch`, `branchPrefix`, `gateCommands`,
  `commitSignArgs`, `openspec` (opt-in), a shared `repoBrief` string injected
  into the built-in stage prompts, role handles (`agent`, `judgeAgent`,
  `reporterAgent`) with `sessionConfig` / `judgeSessionConfig` /
  `reporterSessionConfig`, and defaulted caps.
- Add the glossary term **Meta playbook** to `CONTEXT.md` (a playbook that
  composes std, other playbooks, and deterministic stages over a whole unit of
  work) and update the *Package consumption* export list.
- Replace lace's `.ptah/workflows/issue-worker/` (the ten modules) with a thin
  shim that requires the package and supplies Local config. The dependency
  stays pinned `rev = "main"`; `pesde.lock` records the resolved tree id.

**Non-goals (deliberately deferred):** upstream offline coverage for the new
playbooks (the ptah mock-agent suite) and the stale `README.md` note claiming
no suite exists — both are follow-ups, so this change cuts no tag.

## Capabilities

### New Capabilities

<!-- none: all behavior lives under the existing playbooks capability -->

### Modified Capabilities

- `playbooks`: the *Package consumption* requirement's export list gains
  `std.agent`, `std.shell`, `issueWorker`, and `ciGate`; new requirements are
  added for the stdlib helpers (`std.agent`, `std.shell`), the `issueWorker`
  meta playbook, and the `ciGate` playbook. The existing playbook-facade,
  self-containment, and typed-judge requirements already cover the new units
  and are not restated.

## Impact

- `lib.luau` — new exports.
- `std/agent.luau`, `std/shell.luau` — new modules; `std/gh.luau` and
  `std/daemon.luau` re-route their private helpers through `std/shell`.
- `playbooks/issue-worker/` — new meta playbook (`playbook.luau`, a private
  `git.luau`, and `README.md` declaring environment requirements).
- `playbooks/ci-gate/` — new playbook (`playbook.luau`, `README.md`).
- `CONTEXT.md` — new term **Meta playbook**.
- `openspec/specs/playbooks/spec.md` — updated by the delta.
- `input-output-hk/lace-id-portal` (branch `issue-worker`) —
  `.ptah/workflows/issue-worker/` collapses to a shim; `.ptah/pesde.toml` /
  `.ptah/pesde.lock` re-locked.
- No breaking change to existing consumers: the additions are new exports, and
  `std.gh`/`std.daemon`'s observable behavior is unchanged.
