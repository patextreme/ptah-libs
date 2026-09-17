## Why

`std.worktree.provision` passes an explicit relative `parent` through unchanged even though Git interprets the derived worktree path relative to the selected repository root and records it as an absolute physical path. The mismatch breaks the existing absolute-path and adopt-on-rerun contracts: a healthy registered worktree can be rejected as an unrelated directory, and the returned `Worktree.path` can be relative.

## What Changes

- Define an explicit relative `parent` as relative to the selected repository root, including when Ptah is invoked from a repository subdirectory.
- Resolve the derived target to one canonical physical absolute path and use that identity consistently for worktree inventory lookup, existence checks, Git operations, diagnostics, and the returned `Worktree.path`.
- Treat Git's registered path as authoritative after worktree creation so symlinked parents and other lexical aliases converge on the same identity Git reports.
- Parse the worktree inventory in NUL-delimited porcelain mode so valid paths containing whitespace, non-ASCII characters, quoting characters, or line delimiters are not corrupted or misidentified.
- Preserve the current resolution order and safety policy: registered worktrees are adopted only on the requested branch, dirty state is preserved, and mismatched, detached, or unrelated paths are rejected without mutation.
- Keep the default-parent relocation and creation of missing parent directories out of this change; those remain the scope of issue #21 (`worktree-default-under-ptah`).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playbooks`: clarify the Worktree lifecycle requirement's path identity contract for relative and symlinked parents while retaining its existing adoption and no-reset behavior.

## Impact

- `std/worktree.luau` — target-path resolution, worktree-inventory parsing, lookup consistency, and post-create path readback.
- `std/README.md` and module comments — document repository-root-relative parents and canonical absolute return paths where needed.
- `.work/worktree-verify.luau` — scratch regression coverage for relative, subdirectory, symlinked, unusual-character, adoption, and rejection cases; the repository continues to ship no test suite, per the existing Offline test coverage requirement.
- `openspec/specs/playbooks/spec.md` — Worktree lifecycle contract, applied through this change's delta.
- Pending issue #21 — its full Worktree lifecycle delta must be rebased and refreshed after this change lands so it retains the canonical path semantics.
