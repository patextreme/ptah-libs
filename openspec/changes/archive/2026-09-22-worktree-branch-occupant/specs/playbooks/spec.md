# Spec Delta

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
invocation directory), and an optional `parent` (defaulting to
`<repository root>/.ptah/worktree`, so worktrees live under the
repository's own ptah directory by default — one conventional home for
everything ptah-owned — rather than scattered as siblings of the
repository root). An explicit relative `parent` SHALL resolve against
the selected repository root, not the invocation directory. It SHALL
derive the worktree target as `<parent>/<repo-basename>-<name>`, resolve
that target to the same canonical physical absolute path Git uses for
registration, and return a record carrying that path, the branch, and
the ref. The one canonical path SHALL be used for inventory lookup,
existence checks, Git operations, diagnostics, and the returned record;
after creation, Git's registered path SHALL be authoritative. Worktree
inventory processing SHALL preserve every valid path exactly, including
paths containing spaces, non-ASCII characters, quoting characters, and
line delimiters. When the parent directory does not exist, provision
SHALL create it (including intermediate directories) before resolving
the worktree. When `fetch` is set, provision SHALL fetch the ref's
remote (a plain fetch, no refspec) before resolution.

Because the default parent sits inside the repository's checkout, a
git-ignored `<repo-root>/.ptah/worktree/` is a declared environment
requirement, like `git` on PATH: without it, every worktree is untracked
noise in `git status`. A worktree inside the checkout SHALL be treated as
an accepted, documented trade-off: `git clean -ffdx` in the shared
checkout removes nested worktree directories (a plain `git clean -fdx`
skips nested repositories; branches survive in the shared object store;
uncommitted state does not), and a consumer who cannot accept that passes
`parent` explicitly to place worktrees outside the checkout. When such a
removal (or a manual one) leaves a registration whose directory is gone —
at the target path, or at another path that holds the requested branch —
provision SHALL prune the stale registration; a stale registration at the
target path is re-created there from its surviving branch, and a stale
branch occupant falls through to target resolution. When the registration
survives the prune (a locked worktree), provision SHALL raise — unlocking
is never provision's act, and adoption never returns a path that does not
exist. Pruning is git's global `git worktree prune`, so resolving a stale
registration for the requested branch may also retire another path's stale
registration; that widening of the mechanism's one-path identity is
accepted because a stale registration is dead state no owner can use.

Provision SHALL resolve in this order, and SHALL never reset an adopted
worktree or branch — a crashed run's unpushed commits are never silently
destroyed:

- a registered worktree at the path whose directory is gone (a forced
  clean, a manual removal) is a **stale registration**: it is pruned and
  resolution falls through, re-creating the worktree at the same path
  from its surviving branch; a stale registration that survives the
  prune (a locked worktree) raises — it is never unlocked;
- a registered worktree at the path is **adopted as-is** (its branch must
  match; a mismatch, or an unregistered directory at the path, raises);
- otherwise, when the requested branch is attached to a **different**
  registered worktree (a **branch occupant**), the occupant is resolved
  before any attach: a **live** occupant raises an error naming both the
  occupant path and the target path, and the occupant is left untouched
  (provision never removes another owner's worktree); a **stale** occupant
  is pruned and resolution falls through; a stale occupant that survives
  the prune (a locked worktree) raises — it is never unlocked or removed.
  The occupant check SHALL precede the fast-forward fetch and the attach,
  because git refuses both when the branch is checked out elsewhere;
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

#### Scenario: Stale registration is pruned and the worktree re-created

- **WHEN** a worktree is registered at the derived path but its directory is gone (a `git clean -ffdx` or a manual removal)
- **THEN** provision prunes the stale registration and re-creates the worktree at the same path from the surviving branch, with the attach-as-is and fast-forward-or-fail rules applying as usual

#### Scenario: Locked stale registration raises

- **WHEN** a worktree is registered at the derived path, its directory is gone, and the registration survives the prune (a locked worktree)
- **THEN** provision raises and the locked registration is left for its owner to unlock

#### Scenario: Branch held by a live worktree raises naming both paths

- **WHEN** provision runs with a `branch` attached to a different registered worktree whose directory exists
- **THEN** provision raises an error naming both the occupant path and the target path, and the occupant worktree is left untouched — never removed, switched, or forced

#### Scenario: Branch held only by a stale registration is pruned and provisioned

- **WHEN** provision runs with a `branch` attached to a different registration whose directory is gone (a stale branch occupant)
- **THEN** provision prunes the stale registration and continues, re-creating the worktree at the target path from the surviving branch

#### Scenario: Locked stale branch occupant raises

- **WHEN** a `branch` is attached to a different registration whose directory is gone and whose registration survives the prune (a locked worktree)
- **THEN** provision raises and the locked registration is left for its owner to unlock; provision never unlocks or removes it

#### Scenario: Existing branch fast-forwards against its remote counterpart

- **WHEN** the local branch exists, `ref` is its remote-tracking counterpart, and the branch is behind the remote
- **THEN** the branch is fast-forwarded before the worktree is attached — a no-op when current, never a rebase or reset

#### Scenario: Diverged branch errors loudly

- **WHEN** the local branch has unpushed commits and its remote counterpart has moved
- **THEN** provision raises; reconciling diverged work is a human decision

#### Scenario: Resume case attaches to the surviving branch

- **WHEN** the local branch exists (a previous teardown kept it) and `ref` is that branch
- **THEN** the worktree is attached to the existing branch as-is, preserving its commits

#### Scenario: Default parent lives under the repository's ptah directory

- **WHEN** `parent` is omitted
- **THEN** the worktree path is `<repo-root>/.ptah/worktree/<repo-basename>-<name>`, canonical physical absolute, under the repository's own `.ptah` directory

#### Scenario: Path derivation stays outside the repository

- **WHEN** `parent` is passed explicitly as a directory outside any checkout
- **THEN** the worktree path is `<parent>/<repo-basename>-<name>`, canonical physical absolute, and the worktree lives outside every checkout of the repository — the opt-out for consumers who cannot accept the nested-worktree trade-off

#### Scenario: Missing parent directory is created

- **WHEN** provision runs with the derived parent directory absent (the default `.ptah/worktree` on a first run, or an explicit `parent` pointing at a fresh path)
- **THEN** the parent directory is created with its intermediate directories before the worktree is added, and provision succeeds

#### Scenario: Worktree inside the checkout requires the ignore rule

- **WHEN** a consumer relies on the default parent without git-ignoring `<repo-root>/.ptah/worktree/`
- **THEN** that is a declared environment requirement violation, like missing `git` on PATH: the mechanism proceeds, and the worktree surfaces as untracked noise in `git status` of the shared checkout

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
