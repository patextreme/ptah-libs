## MODIFIED Requirements

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
checkout of the repository). An explicit relative `parent` SHALL resolve
against the selected repository root, not the invocation directory. It
SHALL derive the worktree target as
`<parent>/<repo-basename>-<name>`, resolve that target to the same
canonical physical absolute path Git uses for registration, and return a
record carrying that path, the branch, and the ref. The one canonical
path SHALL be used for inventory lookup, existence checks, Git
operations, diagnostics, and the returned record; after creation, Git's
registered path SHALL be authoritative. Worktree inventory processing
SHALL preserve every valid path exactly, including paths containing
spaces, non-ASCII characters, quoting characters, and line delimiters.
When `fetch` is set, provision SHALL fetch the ref's remote (a plain
fetch, no refspec) before resolution.

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

#### Scenario: Relative parent resolves from the repository root

- **WHEN** provision receives a relative `parent`, including when invoked from a subdirectory of the selected repository
- **THEN** it resolves the parent against the selected repository root and returns the canonical physical absolute worktree path

#### Scenario: Relative-parent rerun adopts the original worktree

- **WHEN** provision is called twice with the same relative `parent`, name, ref, and branch
- **THEN** the second call identifies and adopts the worktree created by the first call without resetting it or changing its status

#### Scenario: Symlinked parent uses Git's physical path

- **WHEN** an explicit parent reaches an existing directory through a symbolic-link alias
- **THEN** provision compares, operates on, logs, and returns the physical absolute path Git records, so a rerun through the alias adopts the same worktree

#### Scenario: Unusual valid paths survive inventory parsing

- **WHEN** a registered worktree path contains spaces, non-ASCII characters, quoting characters, or line delimiters
- **THEN** provision preserves the path exactly and can identify and adopt that worktree

#### Scenario: Dirty worktree is adopted unchanged

- **WHEN** the registered worktree is on the requested branch and contains uncommitted or untracked changes
- **THEN** provision adopts it without resetting, cleaning, stashing, switching, or otherwise changing its status

#### Scenario: Branch mismatch at the path errors

- **WHEN** the registered worktree at the path is on a different branch or detached, or an unregistered directory sits at the path
- **THEN** provision raises and leaves the worktree or directory untouched; adoption never silently switches or discards

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
- **THEN** the worktree path is `<sibling-of-the-repo-root>/<repo-basename>-<name>`, canonical and absolute, never inside a checkout of the repository

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
