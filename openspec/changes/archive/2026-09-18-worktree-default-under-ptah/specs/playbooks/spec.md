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
repository root). It SHALL derive the worktree path as
`<parent>/<repo-basename>-<name>` and return a record carrying the path
(always absolute), the branch, and the ref. When the parent directory
does not exist, provision SHALL create it (including intermediate
directories) before resolving the worktree. When `fetch` is set, provision
SHALL fetch the ref's remote (a plain fetch, no refspec) before
resolution.

Because the default parent sits inside the repository's checkout, a
git-ignored `<repo-root>/.ptah/worktree/` is a declared environment
requirement, like `git` on PATH: without it, every worktree is untracked
noise in `git status`. A worktree inside the checkout SHALL be treated as
an accepted, documented trade-off: `git clean -ffdx` in the shared
checkout removes nested worktree directories (a plain `git clean -fdx`
skips nested repositories; branches survive in the shared object store;
uncommitted state does not), and a consumer who cannot accept that passes
`parent` explicitly to place worktrees outside the checkout. When such a
removal (or a manual one) leaves a registration whose directory is gone,
provision SHALL prune the stale registration and re-create the worktree
at the same path — adoption never returns a path that does not exist.

Provision SHALL resolve in this order, and SHALL never reset an adopted
worktree or branch — a crashed run's unpushed commits are never silently
destroyed:

- a registered worktree at the path whose directory is gone (a forced
  clean, a manual removal) is a **stale registration**: it is pruned and
  resolution falls through, re-creating the worktree at the same path
  from its surviving branch;
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

#### Scenario: Stale registration is pruned and the worktree re-created

- **WHEN** a worktree is registered at the derived path but its directory is gone (a `git clean -ffdx` or a manual removal)
- **THEN** provision prunes the stale registration and re-creates the worktree at the same path from the surviving branch, with the attach-as-is and fast-forward-or-fail rules applying as usual

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
- **THEN** the worktree path is `<repo-root>/.ptah/worktree/<repo-basename>-<name>`, absolute, under the repository's own `.ptah` directory

#### Scenario: Path derivation stays outside the repository

- **WHEN** `parent` is passed explicitly as a directory outside any checkout
- **THEN** the worktree path is `<parent>/<repo-basename>-<name>`, absolute, and the worktree lives outside every checkout of the repository — the opt-out for consumers who cannot accept the nested-worktree trade-off

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
