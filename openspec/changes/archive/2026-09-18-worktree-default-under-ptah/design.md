# Design — worktree-default-under-ptah

## Context

See `proposal.md` (Why). One prior decision governs this area: D9 of
`worktree-aware-playbooks` (archived) chose the repository root's sibling
as the default `parent`, rejecting inside-the-repo paths on two grounds —
untracked noise in every checkout, and aggressive cleans (`git clean
-ffdx`) over nested registered worktrees being "not a fact to build on".
This change reverses
that default and records why the reversal is acceptable.

The implementation surface is small: `std/worktree.luau:185` computes
`parent = options.parent ?? parentOf(root)` and derives
`<parent>/<repo-basename>-<name>`; everything else in the module is
path-agnostic (resolution, adoption, teardown discover the repo from the
path itself).

## Goals / Non-Goals

Goals:

- One conventional home for everything ptah-owned in a consumer repo:
  worktrees default under `<repo-root>/.ptah/worktree/`.
- The existing resolution order absorbs the migration (a rerun re-homes a
  surviving branch to the new location) with zero new special cases.
- The opt-out stays one parameter: `parent` still places a worktree
  anywhere, including outside the checkout.

Non-Goals:

- No per-worktree config file or environment-variable knob: the default
  lives in the library, overrides live in the caller's `provision` call
  (the mechanism accepts no configuration table — that contract stands).
- No automatic `.gitignore` editing by the library: the ignore rule is a
  declared environment requirement, not something `provision` writes.
- No cleanup or detection of leftover sibling-directory worktrees from
  before the migration.

## Decisions

### D1 — Default parent: `<repo-root>/.ptah/worktree`; derivation unchanged

The one-line default change. The derivation keeps its repo-basename
prefix (`<parent>/<repo-basename>-<name>`) even though a per-repo
`.ptah/worktree` makes it redundant: the path shape is in the spec's
Worktree lifecycle requirement, adoption keys on the derived path, and
keeping it turns the migration into "only the parent moved" instead of a
new naming scheme. Alternative (drop the prefix under the new default,
paths become `.ptah/worktree/issue-5`) was rejected: it changes two
things at once, for a cosmetic gain.

*Supersedes D9 of `worktree-aware-playbooks`.* (Delta note: the main
spec's old "Path derivation stays outside the repository" scenario keeps
its title in the delta — the validator enforces scenario-name continuity
within MODIFIED blocks — but its WHEN/THEN is rewritten to the surviving
truth, the explicit-`parent` escape hatch.) D9's two grounds, revisited:

- *Untracked noise in every checkout* — collapses to one line
  (`.ptah/worktree/`) in the one checkout that hosts the default parent.
  The factory's committer prompt already excludes `.ptah` from commits,
  so agent-driven commits never sweep a nested worktree in.
- *`git clean -ffdx` over nested worktrees* — now an accepted, documented
  trade-off instead of a disqualifier: a clean with `-ff` (a plain
  `git clean -fdx` skips nested repositories) deletes the worktree
  directories (branches survive in the shared object store; uncommitted
  state does not; the next provision prunes the stale registration and
  re-creates the worktree, D5). Consumers who run aggressive cleans pass
  `parent` explicitly. The sibling default was never a guard against
  data loss — teardown's refuse-dirty and never-touch-branches contracts
  are, and those are unchanged.

The positive case D9 did not weigh: sibling directories mix per-issue
checkouts into the consumer's workspace parent (often a directory of
unrelated projects), and the worktrees are invisible from the repo they
belong to. Under `.ptah/worktree/`, a repo's automation footprint is
discoverable inside the repo.

### D2 — Provision creates the missing parent

Git's own parent creation for `worktree add` is version-dependent and
declared nowhere here — current git (2.54) happens to create nested
missing parents, but the spec's "provision SHALL create it" must hold by
the library's own act, not by leaning on whatever the local git does —
and the default path adds two levels (`.ptah/worktree`) that do not
exist on a first run. Provision execs `mkdir -p` on the resolved parent after path
derivation, before the registration checks — a fresh path is the only
case that reaches creation, since an adopted worktree returns first and
an unregistered directory at the path raises. Explicit `parent` values
get the same creation, so callers never pre-create directories.

### D3 — The ignore rule is an environment requirement, not library behavior

Three options: the library appends the rule to `.gitignore` (mutating the
consumer's files unrequested — and the spec binds the library to not
write outside its mechanism); the playbooks own it (the playbooks are
git-agnostic by contract); or the consumer declares it. The third wins:
`std` already declares environment requirements (`git`, `gh` on PATH),
and `.ptah/worktree/` ignored joins them. This repository's own
`.gitignore` carries the rule as the reference consumer, and the
`std/README.md` documents it where `git`/`gh` are declared. Spec text
covers the requirement so consumers read it at the contract level.

### D4 — Migration: no special case, by construction

The resolution order already contains the migration. A rerun after the
change derives the new path, finds no registered worktree there, finds no
directory there, finds the surviving `issue-<n>` branch, and attaches it
as-is (or fast-forwards it when `ref` is its remote counterpart). The old
sibling directory stays registered in git's worktree list until a human
removes it (`git worktree remove <old-path>` + `prune`, or plain `rm` +
`prune`) — or until a stale-triggered provision prunes it alongside its
own stale registration (D5): the trigger is the derived path, but git's
prune is repo-wide and removes only registrations whose directories are
already gone, so silent destruction of anything alive stays the failure
class the lifecycle exists to prevent. Documented in the README; no code.

### D5 — Stale registrations self-heal: prune, then the usual order

The nested default makes out-of-band deletions routine: a
`git clean -ffdx` (or a manual `rm -rf .ptah`) removes a registered
worktree's directory while git's registration survives, marked
"prunable". The adopt branch keyed on the registration alone, so the
next provision "succeeded" while returning a nonexistent path — a
silent failure only a manual `git worktree prune` cleared. Provision
now checks the derived path when a registration exists for it:
directory gone means prune the stale registration and fall through to
the usual resolution order, which re-creates the worktree at the same
path from the surviving branch (attach-as-is, or
fast-forward-or-fail when `ref` is its remote counterpart). The check
re-reads the registration after the prune: a stale registration that
survives it — a locked worktree, which git's prune always skips so
one on an unmounted device or network share keeps its admin files —
makes provision raise instead of adopt; unlocking is the registration
owner's decision, never provision's. No new silent failure modes:
teardown already prunes best-effort, and the raise keeps the spec's
absolute rule — adoption never returns a path that does not exist.

## Risks / Trade-offs

- [Nested worktree directories are deletable by `git clean -ffdx` in the
  shared checkout, losing uncommitted state] → documented trade-off with
  the `parent` opt-out; branches (the durable artifact) survive any
  clean, and the next provision prunes the stale registration and
  re-creates the worktree (D5; a locked stale registration raises
  instead).
- [A consumer without the ignore rule sees worktrees as untracked noise,
  and agents may commit the nested checkout's `.git` file as an embedded
  repo] → declared environment requirement in spec + README; the factory
  prompt already excludes `.ptah`; the pesde-shim consumers copy this
  repo's `.gitignore`.
- [Recursive nesting: provisioning from inside a linked worktree] →
  `rev-parse --show-toplevel` in a linked worktree returns that linked
  tree's root, so the default parent becomes
  `<linked-root>/.ptah/worktree` — a worktree nested inside a worktree.
  Git permits it and the ignore-rule requirement covers it, but the
  nested tree is invisible to the main checkout and dies with it on
  teardown. Mitigation is usage shape, stated in the README: provision
  from the shared checkout (as the factory does); a consumer who
  provisions from inside a worktree gets exactly that and meant it.
- [Pre-existing sibling worktrees linger registered after migration] →
  adoption no longer finds them; the migration note tells the human how
  to retire them. No automatic sweep.

## Migration Plan

1. Land the code, spec, docs, and `.gitignore` change together; cut a
   **minor** tag — the repo is pre-1.0 (`0.1.0`) and consumers pin tags,
   so a breaking default is opt-in by re-pinning and the bump is the
   announcement, not a guard (the default is BREAKING for consumers who
   relied on sibling placement).
2. Consumers with in-flight runs: let them finish or accept the re-home —
   the next provision attaches the surviving branch at the new location
   (D4).
3. One-time per repo: `git worktree list`, remove leftover sibling
   directories, `.ptah/worktree/` added to `.gitignore`.

## Open Questions

(none)
