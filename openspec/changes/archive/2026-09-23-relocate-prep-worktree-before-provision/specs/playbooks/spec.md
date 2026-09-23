# Spec Delta

## ADDED Requirements

### Requirement: Worktree occupant introspection

The worktree mechanism SHALL export a pure introspection operation,
`liveOccupant`, that reports the path of the registered worktree
currently holding a given branch when that worktree's directory exists,
and nil when no registration holds the branch or the only registration
is stale (its directory is gone — stale state remains provision's
prune-self-heal business). The operation SHALL accept the branch
(required) and an optional repository (defaulting to the repository of
the invocation directory, like provision's `repo`). The operation SHALL
have no side effects — no prune, no creation, no removal, no fetch, no
branch inspection beyond the inventory provision already parses — and
SHALL carry no policy: it reports; it never removes. The lifecycle
requirement's occupant resolution in provision SHALL be unchanged by
this export.

#### Scenario: Live occupant is reported

- **WHEN** `liveOccupant` is called for a branch attached to a registered worktree whose directory exists
- **THEN** the operation returns that worktree's registered path and mutates nothing

#### Scenario: Stale or absent occupant is nil

- **WHEN** `liveOccupant` is called for a branch no registration holds, or whose only registration's directory is gone
- **THEN** the operation returns nil and performs no prune

#### Scenario: Optional repository defaults like provision

- **WHEN** `liveOccupant` is called without a repository from inside a repository
- **THEN** it resolves the invocation directory's repository, the same default provision applies

#### Scenario: Provision's occupant raise is unchanged

- **WHEN** provision runs for a branch attached to a live occupant
- **THEN** it raises naming both paths and leaves the occupant untouched, exactly as before the introspection export existed

## MODIFIED Requirements

### Requirement: Factory playbook

The library SHALL provide a factory composition playbook that drains a
repository's labeled issue queue into reviewed pull requests by composing
the issue, openspec, and pr playbooks. The factory SHALL construct its
composed playbook instances internally from its own configuration, and
its configuration SHALL NOT accept pre-built playbook instances. Its
Local config SHALL be data only: the work/judge/reporter agent handles
with their ordered session-config entries, the required `queueLabel` with
no default, the optional `claimedLabel`, the required `base` branch with
no default (each issue's worktree branches from `origin/<base>` and its
pull request targets `base`), the free-text `conventions` and
`prContract` prompt fragments injected into the direct-edit and delivery
prompts respectively, the convergence and bounded-retry caps
(`maxReviewIterations`, `resolveChangeAttempts`,
`openPullRequestAttempts`), and the optional `removeOccupantWorktree`
(default `true` — whether the factory may relocate a live occupant of the
issue branch before provisioning; `false` restores provision's occupant
raise). The worktree branch for each issue SHALL be the fixed
`issue-<n>`. openspec SHALL be mandatory in v1: each claimed issue is
resolved to an existing openspec change — driven through groom →
implement → verify — or implemented as a direct edit when no change
applies. The factory SHALL expose no dry-run pass-through.

#### Scenario: The consumer shim shrinks to config

- **WHEN** a consumer replaces its factory logic shim with a `factory.new(config)` call
- **THEN** no orchestration code remains in the shim — claiming, worktree provisioning, change resolution, the openspec lifecycle or direct edit, PR opening, the review loop, and teardown are all library-owned

#### Scenario: Required knobs have no defaults

- **WHEN** `factory.new` is called without `queueLabel` or without `base`
- **THEN** construction raises an error naming the missing field (the queue label and the delivery base are the repository's, never the playbook's)

#### Scenario: Prompt fragments travel as data

- **WHEN** a consumer configures `conventions` or `prContract` free text
- **THEN** the library-owned prompt skeletons carry that text at their declared injection points, and the skeletons' structure is unchanged by the fragment's content

#### Scenario: No playbook instances in config

- **WHEN** a consumer's shim config is type-checked against the factory's config
- **THEN** no field accepts an issue, openspec, or pr playbook instance (they are neither data nor ptah runtime handles)

#### Scenario: Occupant relocation is opt-out

- **WHEN** `factory.new` is called with `removeOccupantWorktree = false`
- **THEN** the factory performs no relocation and an occupied issue branch fails through provision's occupant raise, today's behavior

### Requirement: Factory issue-to-PR operation

The factory SHALL provide `issueToPR(number?)`: claim one issue — the
given number only if eligible, otherwise the oldest eligible — then,
when `removeOccupantWorktree` is not false, relocate any live occupant
of `issue-<n>` before provisioning: the occupant worktree is torn down
with default (refuse-dirty) options, and a teardown refusal SHALL fail
the issue naming the occupant path and the remedy (commit, stash, or
remove it by hand) with the worktree and its contents untouched. The
relocation relocates a checkout; it never discards work, and the branch
survives teardown by contract. The factory then provisions its worktree
on `issue-<n>` off `origin/<base>` — the surviving branch re-attaches
with its commits preserved under provision's fast-forward-or-fail rule —
applies the mapped openspec change or a direct edit, commits, pushes,
and opens the issue-linked pull request (its body carrying `Closes #<n>`
so the issue closes on merge), and runs the convergent PR review loop on
the opened PR. The typed hand-offs SHALL be bounded: the
change-resolution hand-off re-asks up to `resolveChangeAttempts` times
and the PR hand-off up to `openPullRequestAttempts` times, and
exhaustion SHALL fail the issue. On the success path the worktree SHALL
be torn down; a failed issue SHALL keep its worktree as the audit trail
and stay claimed.

#### Scenario: Explicit pickup works one issue

- **WHEN** `issueToPR(42)` is called and #42 carries the queue label, is not foreign-assigned, and is unclaimed
- **THEN** exactly #42 is claimed and driven end-to-end, and an ineligible #42 raises with the reason instead

#### Scenario: Scan mode picks the oldest eligible

- **WHEN** `issueToPR()` is called with no number
- **THEN** the oldest eligible issue in the queue is claimed and driven end-to-end

#### Scenario: Direct-edit fallback

- **WHEN** the change-resolution hand-off submits an empty change name for the issue
- **THEN** the issue is implemented by a direct edit in its worktree under the `conventions` fragment, and the pipeline's later steps proceed unchanged

#### Scenario: Hand-off exhaustion fails the issue

- **WHEN** the delivery session submits no PR URL within `openPullRequestAttempts`
- **THEN** the operation fails with a named error, the worktree is kept, and the claim marker remains on the issue

#### Scenario: Prep hand-off proceeds without manual surgery

- **WHEN** the issue's branch is checked out at a prep worktree holding committed work, and the factory claims the re-queued issue
- **THEN** the prep worktree is removed, the branch re-attaches at the canonical worktree with its commits preserved, and the issue proceeds end to end

#### Scenario: Dirty occupant fails with a remedy

- **WHEN** the live occupant of the issue branch contains uncommitted or untracked changes
- **THEN** the issue fails naming the occupant path and the commit/stash/remove remedy; the worktree and its contents are untouched, and the claim marker stays

#### Scenario: Unoccupied branch behaves as before

- **WHEN** no live registration holds the issue branch (none at all, or only a stale registration whose directory is gone)
- **THEN** provisioning behaves exactly as without the relocation step, stale state still provision's self-heal

#### Scenario: Re-queued interrupted run restarts fresh or fails loudly

- **WHEN** an earlier run of the same issue left its canonical worktree in place and the issue is re-queued
- **THEN** the relocation applies identically: a clean worktree is removed and the issue restarts fresh from `origin/<base>`, while a dirty worktree fails the issue with the remedy instead of resuming in place
