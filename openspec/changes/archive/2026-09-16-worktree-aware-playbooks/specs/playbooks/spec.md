## MODIFIED Requirements

### Requirement: Package consumption

The library SHALL be packaged as a pesde package (`patextreme/ptah_libs`,
`luau` target) consumable as a **git dependency pinned to a tag** of this
repository — never published to a registry — and SHALL expose exactly one
library entry whose exports are the named camelCase surface:
`std` (with `predicate`, `gh`, `daemon`, `sessionConfig`, `escalate`, and
`worktree`), `openspec`, `pr`, and `issue`. Top-level playbook exports are named for the entity
they manage; deep-path requires into the library tree SHALL NOT be part of
the supported consumer surface.

#### Scenario: Consumer installs as a git dependency

- **WHEN** a consumer declares a pesde git dependency on this repository at a tag revision and runs `pesde install`
- **THEN** pesde's generated `luau_packages` shim requires the package entry and re-exports its values and types, and the consumer's shim reaches the library through that generated shim

#### Scenario: Entry exports the library surface

- **WHEN** a consumer requires the generated dependency shim
- **THEN** `std.predicate`, `std.gh`, `std.daemon`, `std.sessionConfig`, `std.escalate`, `std.worktree`, `openspec`, `pr`, and `issue` are available on the returned table

#### Scenario: The renamed export replaces the former name

- **WHEN** a consumer requires the generated dependency shim
- **THEN** `prReviewLoop` is not available on the returned table (the rename is a clean break; consumers pin the prior tag to defer it)

### Requirement: Typed judge

The library SHALL provide a typed boolean judge that asks a designated
judge agent whether a predicate holds for a payload and returns the verdict
from the session's typed boolean result. The judge's options SHALL accept
an agent handle, a session id, a retry bound, an optional ordered array
of session-config entries applied to every judge attempt session before
its prompt, and an optional working directory applied to every judge
attempt session (so a caller running a loop inside a working directory
can keep its judge sessions there too); no dedicated model field SHALL
exist (a model choice is an ordinary session-config entry). A judge that
submits no verdict SHALL be retried a bounded number of times, and
exhaustion SHALL be a script error, never a hang or a silent default.

#### Scenario: Verdict returned

- **WHEN** the judge session submits a boolean verdict for the predicate and payload
- **THEN** the operation returns that verdict

#### Scenario: Judge never answers

- **WHEN** the judge session submits no typed verdict on every attempt up to the bound
- **THEN** the operation raises a script error naming the judge and the attempt count

#### Scenario: Judge sessions receive configured entries

- **WHEN** the judge is invoked with session-config entries
- **THEN** every attempt session receives the entries in declared order before the predicate prompt

#### Scenario: Judge sessions run in the configured directory

- **WHEN** the judge is invoked with a working directory
- **THEN** every attempt session runs in that directory, and a judge invoked without one keeps today's behavior

## ADDED Requirements

### Requirement: Worktree lifecycle

The library SHALL provide a worktree lifecycle mechanism (`std.worktree`)
that provisions and tears down git linked worktrees through ptah's exec,
so consumer shims isolate per-item runs in their own worktree without
managing git state by hand. The mechanism SHALL accept no agent handles
and no configuration table: `git` on PATH is a declared environment
requirement, like the GitHub transport's `gh`.

`provision` SHALL accept a required `name`, a required `ref` (no default —
never the shared tree's HEAD, so a worktree is never silently based on
whatever the shared checkout happens to sit on), an optional `branch`
(defaulting to the ref's short name for remote-tracking refs), an
optional `fetch`, an optional `repo` (defaulting to the repository of the
invocation directory), and an optional `parent` (defaulting to the
repository root's sibling directory, so worktrees never live inside a
checkout of the repository). It SHALL derive the worktree path as
`<parent>/<repo-basename>-<name>` and return a record carrying the path
(always absolute), the branch, and the ref. When `fetch` is set, provision
SHALL fetch the ref's remote (a plain fetch, no refspec) before
resolution.

Provision SHALL resolve in this order, and SHALL never reset an adopted
worktree or branch — a crashed run's unpushed commits are never silently
destroyed:

- a registered worktree at the path is **adopted as-is** (its branch must
  match; a mismatch, or an unregistered directory at the path, raises);
- otherwise, when the local branch exists and `ref` is its remote-tracking
  counterpart, the branch is **fast-forwarded-or-failed** via
  `git fetch <remote> <branch>:<branch>` — a no-op when current, a
  fast-forward when behind, a loud error when diverged (unpushed commits
  and a moved origin is a human decision, not an automatic one) — and the
  worktree is attached to the branch;
- otherwise, when the local branch exists and `ref` is anything else (the
  resume case: the worktree was torn down but the branch survived), the
  worktree is attached to the existing branch **as-is**;
- otherwise the branch is created from the ref (`git worktree add -b
  <branch> <path> <ref>`), with git's upstream auto-set applying for a
  remote-tracking ref — so a plain `git push` from inside the worktree
  pushes the intended branch.

Provision SHALL never rename or prefix branches (an aliased branch name
would make a naive `git push` push the wrong branch), and a failed git
command SHALL raise carrying git's stderr (pcall-able) — there is no
outcome-object form, because a failed provision means the run cannot
proceed.

`teardown` SHALL accept the provision record (any record carrying `path`)
and an optional `force`. It SHALL refuse a dirty worktree by default,
remove and prune otherwise, and SHALL NOT touch branches: unpushed
commits survive on the local branch, and no branch-deletion operation
exists in the mechanism. Teardown SHALL return its outcome as data (`ok`,
and `stderr` on failure) rather than raising — a dirty refusal after a
converged loop is something the caller logs, not a failed run.

#### Scenario: Fresh provision creates a pushable branch

- **WHEN** provision runs with no existing worktree at the path and no local branch
- **THEN** the branch is created from the ref with upstream auto-set for a remote-tracking ref, and a plain `git push` from inside the worktree pushes the intended branch

#### Scenario: Ref is required

- **WHEN** provision is called without a `ref`
- **THEN** it raises; there is no default start point, and never the shared tree's HEAD

#### Scenario: Existing worktree is adopted as-is

- **WHEN** provision runs and a registered worktree exists at the derived path on the requested branch
- **THEN** the existing worktree is returned unchanged — no reset, no re-add — so an interrupted run resumes

#### Scenario: Branch mismatch at the path errors

- **WHEN** the registered worktree at the path is on a different branch, or an unregistered directory sits at the path
- **THEN** provision raises; adoption never silently switches or discards

#### Scenario: Existing branch fast-forwards against its remote counterpart

- **WHEN** the local branch exists, `ref` is its remote-tracking counterpart, and the branch is behind the remote
- **THEN** the branch is fast-forwarded before the worktree is attached — a no-op when current, never a rebase or reset

#### Scenario: Diverged branch errors loudly

- **WHEN** the local branch has unpushed commits and its remote counterpart has moved
- **THEN** provision raises; reconciling diverged work is a human decision

#### Scenario: Resume case attaches to the surviving branch

- **WHEN** the local branch exists (a previous teardown kept it) and `ref` is that branch
- **THEN** the worktree is attached to the existing branch as-is, preserving its commits

#### Scenario: Path derivation stays outside the repository

- **WHEN** `parent` is omitted
- **THEN** the worktree path is `<sibling-of-the-repo-root>/<repo-basename>-<name>`, absolute, never inside a checkout of the repository

#### Scenario: Provision failure raises with stderr

- **WHEN** any git command provision runs fails
- **THEN** provision raises an error carrying git's stderr; no outcome-object form exists

#### Scenario: Clean teardown removes and prunes

- **WHEN** teardown runs on a clean worktree
- **THEN** the worktree is removed and pruned, and the outcome reports success

#### Scenario: Dirty refusal is data, not an error

- **WHEN** teardown runs on a worktree with uncommitted or untracked files and no `force`
- **THEN** teardown returns a failed outcome carrying git's message and raises nothing; the worktree is left in place

#### Scenario: Force overrides the dirty refusal

- **WHEN** teardown runs with `force` on a dirty worktree
- **THEN** the worktree is removed and pruned, discarding the uncommitted changes

#### Scenario: Branches survive teardown

- **WHEN** teardown succeeds on a worktree whose branch has unpushed commits
- **THEN** the local branch and its commits remain — teardown never deletes branches

### Requirement: Playbook working directory

The `openspec` and `pr` playbooks' config SHALL accept an optional
`workingDir`: when set, **every** session the playbook creates — work
sessions, judge sessions, human-escalation-probe sessions, the archive
session, reporter sessions — SHALL run in that directory (ptah's
per-session working directory), so no session of the playbook can read
or write the wrong tree. When `workingDir` is nil, behavior SHALL be
byte-for-byte today's: sessions run in the invocation directory. The
field SHALL be documented as an absolute path.

The playbooks SHALL remain git-agnostic: their config declares no
worktree fields, and provisioning or tearing down a worktree is the
calling shim's business (the worktree lifecycle mechanism is one producer
of working directories; a plain clone is another).

#### Scenario: Every session runs in the working directory

- **WHEN** either playbook is configured with `workingDir` and any operation runs
- **THEN** every session the playbook creates — work, judge, probe, archive, reporter alike — runs in that directory

#### Scenario: Omitted working directory is unchanged

- **WHEN** either playbook is configured without `workingDir`
- **THEN** every session runs in the invocation directory, exactly as before the field existed

#### Scenario: Playbooks never manage worktrees

- **WHEN** a consumer consults either playbook's exported config type
- **THEN** no field provisions, adopts, or tears down a worktree — lifecycle verbs belong to the worktree mechanism, called by the shim
