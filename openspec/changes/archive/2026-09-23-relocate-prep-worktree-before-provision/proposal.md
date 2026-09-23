# Proposal

## Why

The intended hand-off is: a human prepares an issue's openspec change in
their own worktree (`worktrees/issue-37` on branch `issue-37`), commits,
pushes, and re-queues the issue. When the factory later claims it,
`worktree.provision` raises — the branch is already checked out at the
prep path, and the #30/#31 occupant resolution is a std raise, correct at
its layer. Every hand-off-prepared issue therefore fails at claim time
and needs manual worktree surgery before the factory can proceed
(observed on the consumer repo ptah, run `20260923072047-7182`). In this
workflow the occupant is not a rival owner; it is the operator's own prep
artifact for exactly the issue being processed. Deciding to relocate it
is factory orchestration policy, not worktree-domain truth, so it belongs
in the playbook — std keeps its raise untouched.

## What Changes

- `std.worktree` gains one additive export, `liveOccupant`: pure
  introspection returning the path of the registered worktree holding a
  branch when that directory exists, nil for no occupant or a stale
  registration (stale stays provision's prune-self-heal business). No
  policy, no side effects; `provision` and `teardown` semantics are
  unchanged.
- The factory playbook gains a pre-provision relocation step in its
  issue-to-PR operation: before provisioning `issue-<n>`, discover a live
  occupant of the branch and tear it down with default (refuse-dirty)
  options. A teardown refusal fails the issue naming the path and the
  remedy (commit/stash/remove by hand) — the step relocates a checkout,
  it never discards work. The branch survives teardown by contract, and
  provision takes its re-attach path (commits preserved, FF-only fetch
  keeps divergence loud).
- New optional config field `removeOccupantWorktree: boolean?` (default
  `true`); `false` restores today's provision raise for consumers who
  want it.
- Docs: the std README's worktree section documents the `liveOccupant`
  contract; the factory README documents the hand-off contract and the
  new knob.
- Tests: none in this repository (the Offline test coverage requirement
  keeps the suite upstream); the upstream suite's obligations for
  `liveOccupant` unit cases and a relocation-level case are recorded, not
  implemented here.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playbooks`: the worktree mechanism gains an occupant-introspection
  requirement (`liveOccupant`); the Factory playbook requirement gains
  the `removeOccupantWorktree` config knob; the Factory issue-to-PR
  requirement gains the pre-provision relocation behavior and its failure
  semantics, including the re-queued interrupted-run case (an interrupted
  run's worktree is relocated too: clean restarts fresh from
  `origin/<base>`, a dirty one fails the issue with the remedy instead of
  resuming in place).

## Impact

- **Code**: `std/worktree.luau` (one small export composed from existing
  private helpers), `playbooks/factory/playbook.luau` (the relocation
  step, the config field, its wiring).
- **API**: additive — a new public std export; a minor version bump per
  the README versioning contract. `provision`/`teardown` behavior is
  unchanged.
- **Behavior**: factory default behavior changes only for issues whose
  branch is already checked out somewhere — the hand-off case, and
  re-queued interrupted runs. With `removeOccupantWorktree = false`,
  behavior is today's raise.
- **Tests**: none here; upstream obligations recorded in this change.
- **Docs**: `std/README.md`, `playbooks/factory/README.md`.
