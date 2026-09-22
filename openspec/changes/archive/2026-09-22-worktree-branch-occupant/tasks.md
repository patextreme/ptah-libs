# Tasks

## 1. Library mechanism (`std/worktree.luau`)

- [x] 1.1 Add a `branchOccupant(registered, branch)` helper that scans `registered.branches` for the path attached to `branch` (name the loop variable `occupant`/`at`, not `path`); verify by inspection that it reads only the already-parsed inventory and issues no new git call
- [x] 1.2 Insert the occupant guard between the unregistered-directory check and the `branchExists` fork: a live occupant raises the occupant-and-target message; a stale occupant runs `git worktree prune`, re-reads the inventory, re-resolves the occupant, and on a survivor raises the lock-aware stale message (directory gone, registration survived); verify by inspection that the guard precedes the fast-forward `git fetch` as well as `git worktree add`
- [x] 1.3 Update the module header comment: the stale-registration self-heal now covers the registration that holds the requested branch, and `git worktree prune` is global, so resolution may retire another path's stale registration (a deliberate widening of one-path identity); verify the comment matches the implemented order
- [x] 1.4 Confirm with `ptah check std/worktree.luau` that the module stays `--!strict` clean

## 2. Documentation

- [x] 2.1 Update the `std/README.md` `worktree.luau` entry to mention branch-occupant handling: a live occupant raises naming both paths, a stale occupant self-heals, a locked stale occupant raises; verify the entry names no option that does not exist

## 3. Verification harness (`.work/worktree-verify.luau`, uncommitted scratch)

- [x] 3.1 Add a live-occupant case: a second registration holds the requested branch at another path with its directory present, `provision` for a fresh target raises, the error names both the occupant path and the target path, and the occupant worktree is untouched (`git worktree list` still shows it, its HEAD unchanged)
- [x] 3.2 Add a stale-occupant case: the occupant's directory is deleted out-of-band while its registration survives (assert the registration is listed before the re-provision), then `provision` succeeds and returns the target path on the requested branch from the surviving branch
- [x] 3.3 Add a locked-stale-occupant case: lock the occupant, delete its directory, run `provision`, assert it raises with the lock-aware wording, and assert the locked registration survives (never unlocked or removed)
- [x] 3.4 Run `ptah run .work/worktree-verify.luau` and confirm every existing case (fresh, adopt-as-is, fast-forward, diverge, default-parent, stale-target, locked-stale-target, teardown) plus the three new cases pass

## 4. Spec sync and validation

- [x] 4.1 Sync `openspec/specs/playbooks/spec.md`'s Worktree lifecycle requirement from this change's delta (via the sync-specs workflow at verify time, or by hand at apply time as the workflow directs)
- [x] 4.2 Run `openspec validate worktree-branch-occupant --strict` and confirm zero issues
