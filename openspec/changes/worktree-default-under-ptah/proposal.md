## Why

`std.worktree.provision` defaults the worktree parent to the repository root's sibling, so a consumer's workspace parent accumulates one `<repo-basename>-<name>` directory per worktree — factory runs on one repo scatter `issue-<n>` checkouts next to unrelated projects. Everything ptah-owned otherwise lives under the consumer's `.ptah` directory; worktrees are the lone exception, and there is no reason to keep them one.

## What Changes

- **BREAKING**: `provision`'s default `parent` becomes `<repository root>/.ptah/worktree` instead of the repository root's sibling; worktrees live inside the repository's `.ptah` directory by default. Consumers who pass `parent` explicitly are unaffected.
- The path derivation stays `<parent>/<repo-basename>-<name>`; only the default parent changes.
- `provision` creates the default parent directory if missing (git does not create nested parents for `worktree add`).
- The `.ptah/worktree/` ignore rule becomes a declared environment requirement, like `git` on PATH: a worktree inside the checkout is untracked noise in `git status` unless ignored. This repository's own `.gitignore` carries the rule as the reference consumer.
- The factory workflow (`factory/main.luau`) inherits the new default; its path-derivation comments are updated. No behavioral change to its provision/teardown calls.
- Migration is inherent in the existing resolution order: a rerun finds no registered worktree at the new path, finds the surviving `issue-<n>` branch, and attaches it at the new location. Old sibling directories are inert leftovers a human removes by hand.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playbooks`: the Worktree lifecycle requirement's `parent` default changes from "the repository root's sibling directory" to `<repo-root>/.ptah/worktree`, with parent-directory creation and the ignore-rule environment requirement folded into the same requirement.

## Impact

- `std/worktree.luau` — default-parent derivation, parent creation, header/docs comment, `ProvisionOptions.parent` doc.
- `openspec/specs/playbooks/spec.md` — Worktree lifecycle requirement (via delta).
- `.ptah/workflows/factory/main.luau` — comments describing the worktree path (behavior unchanged).
- `.gitignore` — adds `.ptah/worktree/`.
- `.work/worktree-verify.luau` — gains a case exercising the default parent (existing cases pass `parent` explicitly and are unaffected).
- Consumers relying on the sibling default: worktrees move into the repo on the next provision; branches survive, sibling directories linger until hand-removed.
