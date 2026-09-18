## Context

See `proposal.md` for motivation and `specs/playbooks/spec.md` for the updated Worktree lifecycle contract.

`repoRoot()` already returns an absolute physical repository root. In contrast, `provision()` currently concatenates an explicit `parent` verbatim, uses that string as the worktree-inventory key, checks it with a shell command in the invocation directory, passes it to `git -C <root> worktree add` (where Git interprets it relative to the repository root), and returns it. These operations therefore use different coordinate systems.

`registeredWorktrees()` also parses newline-delimited `git worktree list --porcelain` output after globally trimming stdout. Git may quote unusual paths in that format, while line delimiters can be part of a valid path. The resulting string need not equal the path supplied by the caller or recorded by Git.

The pending `worktree-default-under-ptah` change for issue #21 modifies the same path derivation but owns a different policy decision: the default parent and creation of missing parent directories.

## Goals / Non-Goals

**Goals:**

- Establish one path identity before any lookup or mutation and carry it through the whole provision operation.
- Preserve Git's physical path identity across lexical aliases, especially symlinked parents.
- Make inventory parsing lossless for valid filesystem paths.
- Keep every existing branch-resolution and data-preservation guarantee unchanged.
- Leave a clear base for issue #21 to add parent creation and a different default later.

**Non-Goals:**

- No `git worktree repair`, forced add/remove, reset, clean, stash, branch switch, or branch deletion.
- No change to the default parent in this change.
- No new promise to create a missing parent directory; issue #21 owns that behavior.
- No portable abstraction for non-POSIX filesystems; the module already depends on POSIX shell behavior for quoting and existence checks.
- No new test framework in this repository; the existing contract says the durable offline suite lives in the ptah repository.

## Decisions

### D1 — Resolve a relative parent against the selected repository root

After resolving `root`, provision interprets an absolute parent as-is and prefixes a relative parent with `root`. This matches the location Git already chooses when the same relative target reaches `git -C <root> worktree add`, while making lookup, existence checks, diagnostics, and the returned value agree with that behavior.

Invocation-directory-relative resolution was rejected: it would change the location Git currently creates and would make the same `repo` and options resolve differently depending on the caller's working directory.

### D2 — Canonicalize the existing parent physically before deriving the target

Provision resolves the parent to a physical absolute directory, then appends `<repo-basename>-<name>`. Resolving the parent rather than the not-yet-created target handles the normal fresh-create case and collapses symlink aliases before inventory lookup. A POSIX `cd` plus physical `pwd` can perform this without adding a coreutils dependency; all dynamic path values remain shell-quoted.

Lexical normalization alone was rejected because an absolute path that retains a symlink component still does not equal Git's registered physical path. Canonicalizing only after creation was also rejected because pre-create existence and registration checks must use the same identity to avoid touching the wrong directory.

A missing parent continues to fail in this change, matching current support. When issue #21 adds parent creation, its implementation must create the resolved parent first and then apply this physical-canonicalization step before deriving the target.

### D3 — Parse NUL-delimited porcelain without trimming stdout

Worktree inventory uses `git worktree list --porcelain -z`. The parser consumes NUL-delimited fields, starts a record at each `worktree <path>` field, and associates a following `branch refs/heads/<name>` field with that exact path. Empty separators and unrelated fields are ignored; absence of a branch leaves the worktree classified as detached.

The inventory path bypasses the generic stdout `trim()` behavior so leading/trailing path characters and record delimiters remain intact. Other Git calls may keep their existing trimmed text behavior.

Implementing Git's C-style quoting rules for non-`-z` porcelain was rejected as more code with more malformed-input edge cases. Human-oriented `git worktree list` output was rejected because it is not a stable machine format.

### D4 — Re-read Git's inventory after creation and return its key

After `git worktree add` succeeds, provision reads the inventory again, requires the canonical target to be registered on the requested branch, and returns the exact path key reported by Git. This makes Git the final source of truth and catches any unexpected disagreement instead of returning an unverified lexical path.

Returning the precomputed path without readback was rejected because the contract specifically aligns `Worktree.path` with registration identity. Running `git worktree repair` was rejected because the affected registration is healthy and repair would broaden mutation policy.

### D5 — Keep resolution and rejection policy unchanged

Canonicalization occurs before the existing sequence: optional fetch, registered-path adoption and branch verification, unregistered-path refusal, existing-branch attach/fast-forward, or new-branch creation. Adoption does not inspect or modify dirty state. A detached worktree remains a branch mismatch, and an unrelated existing directory remains untouched.

This change does not use canonicalization as permission to switch, reset, remove, or repair anything.

### D6 — Coordinate, rather than combine, with issue #21

This change lands first because it fixes path identity under the current default. Issue #21 is then rebased and its full `MODIFIED` Worktree lifecycle block is refreshed to retain this change's relative-parent, physical-path, and inventory guarantees while adding its own default-parent and parent-creation behavior.

Combining them was rejected because it would delay a correctness fix behind a breaking default change and obscure which behavior belongs to which issue.

## Risks / Trade-offs

- [The runtime or `ptah.exec` could fail to preserve embedded NUL bytes] → verify NUL round-tripping before relying on the parser; fail implementation verification rather than falling back silently to lossy line parsing.
- [Physical parent resolution uses POSIX shell behavior] → use shell built-ins with the module's existing quoting helper and document no new executable dependency.
- [Post-create readback can detect an unexpected mismatch after Git has already created the worktree] → raise loudly and leave the healthy worktree registered for safe manual inspection or a rerun; never remove it automatically.
- [Issue #21's full requirement delta can overwrite these semantics when archived] → make refreshing that delta an explicit follow-up and sequencing constraint.
- [The local scratch verification is not durable regression coverage] → exercise every acceptance path locally and note that durable offline coverage belongs in the ptah repository under the existing Offline test coverage requirement.

## Migration Plan

1. Land this change and archive its delta into the main `playbooks` spec.
2. Rebase branch `issue-21` onto the resulting main branch and update `worktree-default-under-ptah` so its full Worktree lifecycle delta includes these semantics.
3. Consumers require no data migration: existing registered worktrees are discovered under Git's current physical paths and adopted unchanged.
4. Rollback is a normal code/spec revert; no worktree or branch metadata is rewritten by this change.
