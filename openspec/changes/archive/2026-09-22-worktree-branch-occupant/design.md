# Design

## Context

See `proposal.md` — Why, and the delta spec at `specs/playbooks/spec.md`
for the required behavior.

`std/worktree.luau` already parses the worktree inventory into two maps —
`registered.paths` (path → registered) and `registered.branches`
(path → branch) — losslessly from NUL-delimited porcelain. Every existing
conflict check consults `paths` only; `branches` is read only for the
adopt-as-is branch comparison. Provision's resolution is: stale target
registration (prune) → adopt-as-is at the target path → unregistered
directory at the target path (raise) → `branchExists` fork (fast-forward
fetch + `worktree add <path> <branch>`, or `worktree add -b <branch>
<path> <ref>`).

Git ties a branch to at most one worktree registration and refuses both
`git worktree add <path> <branch>` and `git fetch <remote>
<branch>:<branch>` when that branch is attached to another registration
(live or stale, `prunable` included). Provision currently sees neither
refusal as anything but an opaque git fatal, and it never prunes a stale
registration for any path but its own target. Confirmed against git
locally: a live occupant fails both commands; a stale occupant fails
`worktree add` with the occupant named, and `git worktree prune` clears it
so the subsequent add succeeds; a locked stale occupant survives the prune.

## Goals / Non-Goals

**Goals:**

- Detect a branch occupant from the association already parsed, without a
  new git query.
- Self-heal a stale occupant exactly as a stale target registration
  self-heals, and fail loudly on a live one with a message naming both
  paths.
- Keep the check ahead of every command git refuses for an occupied
  branch (the fetch as well as the attach).

**Non-Goals:**

- No new public API, option, or config knob: the mechanism still accepts
  no configuration table.
- No change to `teardown`, adopt-as-is, fast-forward-or-fail, the resume
  attach, or branch creation.
- Not attempting to make two live checkouts of one branch possible; that
  is a divergent-history hazard, not a feature.

## Decisions

### D1 — Reverse lookup over the parsed association, placed before the `branchExists` fork

Add a `branchOccupant(registered, branch)` helper scanning
`registered.branches` for the path attached to `branch`. The guard runs
after adopt-as-is and the unregistered-directory check (so an adopted or
rejected target path keeps its current behavior and error) and before the
`branchExists` fork.

Placement before the fork — not merely around `git worktree add` — is
required: when `ref` is the branch's remote-tracking counterpart the
resume path first runs `git fetch <remote> <branch>:<branch>`, and git
refuses to fetch into a branch checked out elsewhere. Guarding only the
attach would still surface an opaque fetch fatal.

The lookup iterates `pairs()`; a live-first or stale-first bias is
unnecessary because git refuses a second registration for an
already-attached branch, so at most one registration ever holds a given
branch. Name the loop variable `occupant` (or `at`), not `path` — the
target `path` is live in scope and Luau permits the shadow, but it reads
as a bug.

### D2 — A stale occupant self-heals through the existing global prune

If the occupant's directory is gone, run `git worktree prune` (already
used for the stale-target case), re-read the inventory, and re-resolve the
occupant. This is the same self-heal the module documents for its own
target; the only difference is that the trigger is branch identity rather
than path identity.

`git worktree prune` is global — it retires **every** prunable
registration, not the occupant alone. This deliberately widens the module
header's "one path identity rules a provision run" invariant: resolution
may now retire another path's stale registration. It is accepted because a
prunable registration is dead state (its directory is gone) that no owner
can use, and git offers no path-scoped prune. The module header comment
must state the widening.

Alternative considered and rejected: removing the occupant's registration
with `git worktree remove`/hand-editing admin files. That is a
path-scoped act against another owner's registration and can fail or
damage state on an unmounted device; prune is the only operation whose
semantics match "this registration is dead".

### D3 — Two error messages: live occupant and locked stale occupant

After the prune-and-re-resolve, a surviving occupant is either live (its
directory exists) or a locked stale registration (directory gone, prune
skipped it). They get distinct messages:

- live: `worktree: branch {branch} is already checked out at {occupant};
  remove that worktree before provisioning {path}`
- locked stale: `worktree: branch {branch} is held by a stale registration
  at {occupant} whose directory is gone and the registration survived
  prune (a locked worktree?); unlock it or run git worktree prune by hand`

The second mirrors the existing locked-stale-target message. The issue's
sketch let this case fall through to the live-occupant wording, which
claims the branch is "checked out at" a path that does not exist and
tells the operator to "remove that worktree" — misleading for dead
registration state. The acceptance criterion is only "raises"; this design
chooses the lock-aware wording for operator clarity and consistency.

### D4 — Reject the two force/adopt shortcuts

- `git worktree add --force`: permits two live checkouts of one branch,
  each able to commit divergent history. Wrong.
- Adopting the foreign worktree: violates path identity and transfers
  teardown ownership — `teardown` takes `{path}` and would later remove a
  registration another owner owns.

## Risks / Trade-offs

- **Global prune retires unrelated stale registrations** → they are dead
  state by definition (directory gone, unlocked); the existing
  stale-target path already prunes globally, so the blast radius is
  unchanged in kind.
- **Determinism of `pairs()` if two registrations ever named one branch**
  → not reachable through supported git operations; if it ever occurred,
  the guard still raises for a live holder, so the failure stays loud.
- **TOCTOU between the guard and the attach** → another process can still
  grab the branch after the check; git then fails with its own fatal,
  which provision already raises. The guard narrows the window and fixes
  the common case; it does not claim mutual exclusion.
- **Behavior change for consumers relying on the git fatal** → none
  sensible; the old behavior was an opaque error, the new one is an
  actionable error or a successful self-heal.
