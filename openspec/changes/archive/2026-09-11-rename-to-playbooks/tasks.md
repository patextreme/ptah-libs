## 1. Move the library tree

- [x] 1.1 `git mv factory-components/std std` and `git mv factory-components/components playbooks`; verify `git status` records renames (not delete+add), `std/` and `playbooks/` hold the expected modules, and no `factory-components/` directory remains
- [x] 1.2 `git mv playbooks/openspec/component.luau playbooks/openspec/playbook.luau` and the same for `pr-review-loop`; verify `find . -name component.luau` returns nothing
- [x] 1.3 Confirm the moved modules' internal requires are untouched and still resolve: each playbook's `require("../../std/…")` resolves to `std/` (both are two levels below the package root) — verify with `grep -rn 'require(' std playbooks` and a `ptah check` on a scratch shim

## 2. Rewire the package surface

- [x] 2.1 Update `lib.luau`'s requires to `./std/…` and `./playbooks/…/playbook` (and its header comment); verify `ptah check` on a scratch shim requiring the entry passes with exit 0
- [x] 2.2 Update `pesde.toml`: `includes = ["lib.luau", "std/**", "playbooks/**", "README.md", "LICENSE", "pesde.toml"]` and rewrite the description; verify every tracked file the library needs is matched by an include glob (`git ls-files`)
- [x] 2.3 Retarget `.luaurc` to `{ "aliases": { "ptah_libs": "./" } }`; verify a scratch script requiring `@ptah_libs/std/predicate` and `@ptah_libs/playbooks/pr-review-loop/playbook` passes both `ptah check` and `ptah run`
- [x] 2.4 Update the gitignored in-repo shim `.ptah/workflows/adhoc/main.luau` to `require("@ptah_libs/playbooks/pr-review-loop/playbook")`; verify `ptah check .ptah/workflows/adhoc/main.luau` passes

## 3. Consolidate docs and glossary

- [x] 3.1 Merge the library README into the root `README.md` (consumption + internals + loop conventions), delete `factory-components/README.md`; verify the merged Layout matches the new tree and no `factory-components/` path remains anywhere in `README.md`
- [x] 3.2 Update `std/README.md` and `playbooks/README.md` (the former components README) wording and paths; verify no "component" unit references remain in either
- [x] 3.3 Rename the `CONTEXT.md` terms — **Factory Components** → **Ptah Playbooks**, **Component** → **Playbook** — parking the old names in the new terms' `_Avoid_` lists, and update the title line; verify `grep -in 'factory components\|component' CONTEXT.md` shows only avoided-term entries
- [x] 3.4 Fix the stale reference in the docs to a non-existent `2026-09-04-factory-components` archived change; verify the path either exists or is removed

## 4. Sync the capability rename

- [x] 4.1 Archive the change so the deltas merge: `playbooks` is created and `factory-components` is retired; verify `openspec list --specs` lists `playbooks` (and not `factory-components`) and `openspec/specs/factory-components/` no longer exists
- [x] 4.2 Verify `openspec validate --specs` passes and the new `playbooks` spec carries all 12 requirements with their scenarios

## 5. Verify end to end

- [x] 5.1 `ptah check .ptah/workflows/adhoc/main.luau` exits 0 (alias, entry, and library tree all resolve)
- [x] 5.2 A Helix (luau-lsp) pass over a file requiring `@ptah_libs/playbooks/…` shows no unresolved-require diagnostic and surfaces library type errors through the alias
- [x] 5.3 `git status` shows only the renames and edits this change intends; no `factory-components/` path and no `component.luau` file remain
