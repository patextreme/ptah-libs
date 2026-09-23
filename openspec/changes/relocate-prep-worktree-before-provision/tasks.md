# Tasks

## 1. std: `liveOccupant` export

- [ ] 1.1 Add `liveOccupant(options: { branch: string, repo: string? }): string?` to `std/worktree.luau`, composed from the existing private `registeredWorktrees`/`branchOccupant`/`pathExists`, with the module doc-comment contract (live occupant only; stale or absent → nil; no side effects); verify by requiring the module and confirming the type gate accepts a call site (`ptah check` on a minimal shim)
- [ ] 1.2 Document the `liveOccupant` contract in the worktree section of `std/README.md` (introspection only: reports, never removes; provision's raise unchanged); verify the README states all three properties — live-only, stale-nil, no-side-effects

## 2. factory: relocation step

- [ ] 2.1 Add the optional `removeOccupantWorktree: boolean?` (default `true`) to the factory `Config` type and its doc comment, and thread it into the `workIssue` closure; verify construction still raises on missing `queueLabel`/`base` and the type gate accepts a config omitting the new field
- [ ] 2.2 In `workIssue`, immediately before `provision` and behind the `removeOccupantWorktree ~= false` guard: `liveOccupant` the branch, log the relocation with the playbook's error prefix, `teardown` the occupant with default options, and on refusal raise naming the path and the commit/stash/remove remedy; verify the flow reads 1:1 against the delta spec's scenarios (prep hand-off, dirty occupant, unoccupied branch, knob off)

## 3. Docs

- [ ] 3.1 Document the hand-off contract in `playbooks/factory/README.md`: prepare the change in `worktrees/issue-<n>`, push, re-queue, and the claim relocates the prep worktree; include the `removeOccupantWorktree` knob and the dirty-occupant failure remedy; verify the README's steps match the spec scenarios

## 4. Verification and release

- [ ] 4.1 Exercise the hand-off end to end on a scratch repo (or the consumer repo): a clean occupant → relocated, issue proceeds; a dirty occupant → `failed` outcome naming the path and remedy, contents untouched, claim marker kept; a `removeOccupantWorktree = false` run → today's provision raise
- [ ] 4.2 Record the upstream coverage obligations against the ptah test-suite tracking issue: `liveOccupant` unit cases (live, stale, absent, `repo` defaulting, provision-raise-unchanged) and a `workIssue`-level relocation case (clean, dirty, knob off); verify the obligations are visible where the upstream suite will be written
- [ ] 4.3 At release: bump the minor version (new public export) per the README versioning contract; verify `pesde.toml` version and the README table agree
