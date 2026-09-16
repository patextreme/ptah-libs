# Design — worktree-aware playbooks

## Context

See `proposal.md` (Why) and the `playbooks` delta spec (the behavioral
contract: *Worktree lifecycle*, *Playbook working directory*, the amended
*Typed judge* and *Package consumption*). The full decision record —
twelve questions with alternatives — lives in issue #11; this document
records each decision with its rationale and the implementation shape.

Two vocabulary terms keep the design honest:

- **working dir** — the playbook's `workingDir` config: any absolute
  directory the sessions run in. The playbooks stay git-agnostic.
- **worktree** — the git linked checkout `std.worktree` provisions; one
  *producer* of working dirs.

## Goals / Non-Goals

Goals:

- A playbook run can be pointed at a directory it does not share with
  any other run, with every session it creates inside that directory.
- A shim can provision, resume, and dispose of worktrees in a handful of
  lines, with no silent data destruction anywhere in the lifecycle.

Non-Goals (design-level, beyond the proposal's scope line):

- No auto-provisioning/teardown inside playbook operations (see D3).
- No concurrency coordination between provision calls (see D10).
- No PR-aware provisioner: `std.worktree` knows git, not GitHub — the
  PR-head case is `ref = "origin/<branch>"`, and deriving the branch
  name (`gh pr view --json headRefName`) is shim code.

## Decisions

### D1 — `workingDir` is config, not a per-call argument

The playbook contract says per-call data is a method argument — and a
worktree *is* derived from per-call identity (the PR's branch, the
change's branch), which argued per-call. Rejected: the directory is the
environment the whole instance operates in (like `dryRun`), one instance
floating across directories mid-run would smear the `pr-review:<n>`
session-id sequence across different trees in one log stream, and every
signature would grow an options table. `new()` creates no sessions, so
instance-per-worktree is cheap; a `ptah.parallel` fan-out gives each lane
its own instance and log stream. Nil keeps today's behavior
byte-for-byte.

### D2 — Uniform coverage: every session gets the cwd

Judges, reporters, and probe sessions are text-in/typed-out *in
principle*, but nothing stops those agents from exploring with their
tools — and a judge that looks reads the invocation dir at whatever
branch the shared tree sits on: a silent wrong-repo hazard. One contract
sentence ("every session the playbook creates") kills the hazard and
costs one std option: `PredicateOptions.cwd`, forwarded to every judge
attempt session (also useful to third consumers on its own).

### D3 — Playbooks stay git-agnostic; lifecycle belongs to the shim

Auto-provision inside `review()` was rejected: the openspec lifecycle is
asymmetric (the worktree must outlive the run until the branch is pushed
and the PR opened — auto-teardown would destroy work), error-path
teardown needs pcall discipline the shim can own visibly, and a caller
may want to inspect a worktree after a non-converged loop. The playbook
being *aware* of directories (cwd) without *owning* them (provision) is
the split.

### D4 — `std/worktree` is transport with policy as parameters

The std bar is "mechanisms a third consumer would use verbatim", and the
defaults (adopt-on-rerun, refuse-dirty teardown) are policy — but
parameterized policy, exactly as `gh` encodes a quoting policy as part
of its mechanism. It is not a playbook (no agent, no operations) and not
merely a documented pattern (the sharp git edges would land in every
shim — see D5).

### D5 — Branch topology: same-named local branch, always

Three traps a naive `worktree add` wrapper strands the consumer in:

- `git worktree add <path> origin/x` → **detached HEAD**: the fix turn's
  "push to the PR branch" then does the wrong thing.
- `git worktree add <path> x` → fails when `x` is checked out in another
  worktree — the old shim pattern we are retiring.
- a `wt/x`-style alias branch → a naive `git push` pushes the wrong
  branch.

So: `branch` defaults to the ref's short name; explicit for the openspec
case (`ref = "main"`, `branch = "openspec/add-auth"` — derivation there
would commit onto main). Creation uses `git worktree add -b <branch>
<path> <ref>` so git's upstream auto-set applies and a plain `git push`
works.

### D6 — Resolution order: adopt as-is, fast-forward-or-fail, never reset

A crashed fix turn can hold committed-but-unpushed work; silent
destruction is the worst failure this API could carry. Adopt-as-is
covers the worktree-exists case. For the branch-exists cases:

- ref is the branch's remote-tracking counterpart → `git fetch <remote>
  <branch>:<branch>` — a no-op when current, a fast-forward when behind
  (the common PR re-run: the author pushed since), a loud error when
  diverged (crashed-unpushed + moved origin is a human decision). The
  `src:dst` refspec gives all three semantics natively in one exec.
- ref is anything else (typically the surviving branch itself — the
  resume case after a teardown kept it) → attach as-is.

### D7 — Asymmetric failure shape

`gh` returns outcomes-as-data because its results are domain data
scripts branch on. Provision failure means the run cannot proceed at
all — closer to ptah-exec's "could not run": **provision raises**
carrying git's stderr (pcall-able), returns the typed record on success.
Teardown failure — a dirty refusal is the *expected* post-crash outcome,
and it happens after a possibly-converged loop — would turn a successful
review into a failed script run: **teardown returns `{ ok, stderr? }`**
and the shim logs it.

### D8 — Teardown: refuse-dirty default, never branches

`git worktree remove` refuses dirty trees; `--force` discards — default
refuse, `force` opt-in. Unpushed commits are *not* destroyed by removal
(the branch survives in the shared object store) — only branch deletion
destroys them, so branch deletion is entirely outside the API; a caller
who means it execs `git branch -d` (which itself refuses unmerged) with
intent. Always `git worktree prune` after.

### D9 — Path derivation: sibling of the repo root

`name` + optional `parent` (default: sibling of the repo root, path
`<parent>/<repo-basename>-<name>`). Inside-the-repo paths were rejected:
a worktree nested in one checkout is untracked noise in every other
checkout of the repository (each needing an ignore rule), and whether
`git clean -fdx` respects nested registered worktrees is not a fact to
build on — outside the tree, the question never arises. `ref` is
required with no default: git's default is the shared tree's HEAD,
"based on whatever the shared checkout sits on" is the bug class this
change kills.

### D10 — No lock API

git's internal worktree locking plus adoption covers concurrent
provision; two lanes provisioning the same name is a caller bug that
errors loudly (mismatch or exists). `repo` exists as an option precisely
so `std.daemon`'s per-repo operations can provision per-repo worktrees
as consumer code.

### D11 — Dogfood: independent-from-main

`changes.luau` stacked branches because it shared one tree. Worktrees
make independent-from-main possible — parallel-safe, merge-order-free —
at the cost of occasional cross-PR conflicts stacking hid. Stacking
remains available to any consumer via `ref` (point it at the previous
change's branch). `pr-reviews.luau`'s hand-maintained branch table is
replaced by `gh pr view --json headRefName`.

## Risks / Trade-offs

- [ptah's relative-`cwd` resolution is unspecified] → provision
  guarantees an absolute path (`git worktree list --porcelain` is the
  truth source) and `workingDir` is documented absolute; the ambiguity
  never matters.
- [A branch requested by a worktree is still checked out in the shared
  tree during migration] → git's "already used by worktree" error
  surfaces through provision's raise; the migration is to stop checking
  PR/change branches out in the shared tree (the dogfood retrofit does
  exactly this).
- [Teardown-as-data can be silently ignored by a sloppy shim] → the
  README pattern shows the log-and-continue (or log-and-stop) handling;
  visibility of the worktree dir in the workspace is the backstop.
- [Two concurrent loops on one PR] → pre-existing requirement (one loop
  per PR), unchanged by worktrees; worktrees only make *parallel lanes
  across different items* safe, which is the point.
- [Worktree sprawl when teardown never runs (crashed shims)] → adopt
  makes a re-run reuse rather than duplicate; the sibling-path
  convention makes stragglers visible next to the repo.

## Migration Plan

Additive: consumers adopt `workingDir`/`std.worktree` by choice; nothing
existing changes. This repo's two adhoc shims switch in the same change
(as tasks) — including retiring shared-tree `git checkout` of PR/change
branches, which unblocks the "already used by worktree" edge above.
Rollback for consumers is pinning the prior tag; for the shims, reverting
the two workflow files.
