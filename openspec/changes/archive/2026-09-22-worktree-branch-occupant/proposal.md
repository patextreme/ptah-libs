# Proposal

## Why

`std.worktree.provision` raises git's `fatal: '<branch>' is already used by
worktree at '<path>'` whenever the requested `branch` is attached to a
**different** registered worktree. Provision detects conflicts only by its own
target path and never consults the branch→worktree association it already
parses (`registeredWorktrees().branches`), so the resume path blindly runs
`git worktree add <target> <branch>` and git refuses. The error names only the
occupant path, so it reads as unrelated to the requested worktree, and a stale
occupant (directory deleted, registration surviving) can never self-heal
because provision only prunes stale registrations for its own target path.
A downstream consumer loses one issue per run — or fails on every run while
the foreign or stale registration persists.

## What Changes

- `provision` consults the registered branch→worktree association and handles a
  `branch` already attached to another worktree, before the fast-forward /
  resume fork:
  - **live occupant** → raise, naming both the occupant path and the target
    path; the occupant is left untouched (provision never removes another
    owner's worktree);
  - **stale occupant** (directory gone, registration survives) → prune and
    continue, re-creating the target on the requested branch from the
    surviving branch, exactly as for a stale target registration;
  - **stale occupant that survives the prune** (a locked worktree) → raise with
    a lock-aware message; it is never unlocked and never removed.
- The stale-registration self-heal widens from "my target path" to "any
  registration that currently holds the requested branch". `git worktree prune`
  is global (already used for the stale-target case), so it may retire another
  path's stale registration — a deliberate, documented deviation from "one path
  identity rules a provision run".
- The occupant guard runs before the fast-forward
  `git fetch <remote> <branch>:<branch>` as well as before `git worktree add`,
  because git refuses both when the branch is checked out in another worktree.
- Unchanged: adopt-as-is, stale-target self-heal, fast-forward-or-fail, the
  resume attach, branch creation from the ref, `teardown`, and the
  never-reset / never-rename / never-unlock policy.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playbooks`: the Worktree lifecycle requirement gains branch-occupant
  resolution in `provision` — a branch held by another registered worktree is
  detected from the parsed branch→worktree association; a live occupant raises
  naming both paths, a stale occupant is pruned and provisioned, and a locked
  stale occupant raises. The stale-registration self-heal is stated over "the
  registration that holds the branch", not only "the target path".

## Impact

- `std/worktree.luau` — new reverse-lookup (`branchOccupant`) and occupant guard
  before the `branchExists` fork; module header comment updated for the widened
  self-heal.
- `openspec/specs/playbooks/spec.md` — Worktree lifecycle requirement (via
  delta).
- `std/README.md` — the `worktree.luau` entry mentions branch-occupant
  handling.
- `.work/worktree-verify.luau` — the uncommitted scratch harness gains
  live-occupant, stale-occupant, and locked-stale-occupant cases.
- Consumers gain self-heal for a branch held by a stale registration and a
  clear, actionable error for a live one. No API or config change.
