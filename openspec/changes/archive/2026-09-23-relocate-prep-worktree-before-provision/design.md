# Design

## Context

`std.worktree` resolves a branch occupant inside `provision` with
module-private helpers (`registeredWorktrees`, `branchOccupant`,
`pathExists`) and raises on a live occupant — correct as worktree-domain
law (#30/#31), but unreachable for orchestration above it. The factory's
`workIssue` calls `provision` with no occupant handling, so a
hand-off-prepared issue (branch checked out at the operator's prep
worktree) fails at claim time. The proposal scopes the fix; this design
pins the shapes. The factory playbook is data-config composition
(ADR 0006); `workIssue` runs behind the per-issue error boundary, so a
raise inside it is a `failed` outcome with the claim marker kept.

## Goals / Non-Goals

**Goals**

- A human prep worktree never blocks the factory: one claim, one clean
  relocation, issue proceeds.
- Refuse-dirty guards every removal: the step relocates checkouts, it
  never discards work.
- Std stays policy-free; the knob is one optional boolean.

**Non-Goals**

- No provision-level occupant policy (the `error | replace | adopt`
  enum was considered and set aside — policy belongs to the playbook;
  see proposal's lineage).
- No adoption/resume semantics anywhere; std's occupant raise and
  adopt-as-is text stay verbatim.
- No tests in this repository (Offline test coverage requirement keeps
  the suite upstream); this change records the obligations only.
- No per-issue knob granularity; the opt-out is per construction.

## Decisions

**1. Additive introspection export, not a provision option.**
`liveOccupant` composes the three existing private helpers; `provision`
is untouched, so `removeOccupantWorktree = false` restoring today's
raise is automatic. Alternative rejected: teaching `provision` a
`replace` mode — that moves factory policy into std and widens the
mechanism's "never removes another owner's worktree" law.

**2. Signature: `liveOccupant(options: { branch: string, repo: string? }): string?`** —
a table, matching `provision`'s public surface, with `repo` defaulting
to the invocation directory's repository exactly like provision's.
This consciously refines the issue's sketch (`liveOccupant(root,
branch)`): the factory playbook never resolves a repository root today
— provision derives it internally — so a required `root` would force
the playbook to grow its own `git rev-parse`, duplicating std logic the
module already owns. Alternative rejected: positional `(root, branch)`.

**3. Teardown with default options is the whole guard.** The factory
never passes `force`; a dirty occupant makes teardown return
`{ ok = false, stderr }`, and `workIssue` raises a wrapped error naming
the path and the remedy (commit/stash/remove by hand) — the existing
per-issue boundary turns that into the `failed` outcome. Locked
occupants ride the same path: git refuses the removal, the stderr says
so. The branch always survives teardown by contract; provision then
re-attaches under fast-forward-or-fail, keeping divergence loud.

**4. Default on.** Claim-marker serialization means the only possible
occupants of `issue-<n>` are the operator's own artifacts: a prep
worktree for this very issue, or a manual checkout of the branch.
Default-on makes the documented hand-off just work; the knob exists for
consumers who want the raise as a tripwire.

**5. The relocation applies to every live occupant, including the
factory's own interrupted-run worktree.** Today a re-queued crashed
issue resumes in place via provision's adopt-as-is path; with the step
in front, it restarts fresh from `origin/<base>` (clean worktree) or
fails with the remedy (dirty). Accepted deliberately: fresh-from-origin
is deterministic and honors the FF-only contract, while resuming
half-baked agent state after a crash is exactly what a fresh start
avoids. Spec'd as its own scenario rather than special-cased away
(skipping relocation when the occupant path is the canonical target was
considered and rejected — it would keep two recovery stories alive).

**6. Placement: first statements of `workIssue`, before `provision`,
inside a `removeOccupantWorktree ~= false` guard.** Introspection logs
the relocation (`ptah.log` with the playbook's error prefix) so the
claim-marker audit trail records what moved.

## Risks / Trade-offs

- [Check-then-remove races an editor saving into the prep worktree] →
  refuse-dirty makes the worst case a loud failed issue, never data
  loss; the window is the same one any teardown already has.
- [Introspection result is stale by the time provision runs] → benign:
  a vanished occupant falls through to provision's own resolution; a
  new occupant raises as it would today.
- [Locked prep worktree] → git refuses the removal; the wrapped error
  fails the issue naming the lock — unlocking is never the factory's
  act, same law as provision's.
- [Fresh-restart semantics surprise a consumer who relied on resume] →
  the knob restores the old raise, and the delta spec names the new
  scenario explicitly; release notes call it out.

## Migration Plan

None required: additive export, additive config field, behavior change
only on the occupied-branch path this change exists to fix. Rollback is
`removeOccupantWorktree = false` (behavioral) or revert (mechanical).
Next release bumps minor (new public export) per the README versioning
contract.

## Open Questions

None.
