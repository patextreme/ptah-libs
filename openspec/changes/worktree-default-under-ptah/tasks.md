# Tasks — worktree-default-under-ptah

## 1. Library mechanism (`std/worktree.luau`)

- [ ] 1.1 Change the default `parent` to `{root}/.ptah/worktree` (keep the `<parent>/<repo-basename>-<name>` derivation); verify by reading the derived path in a scratch provision against this repo
- [ ] 1.2 Create the resolved parent directory (`mkdir -p` via `ptah.exec`) after path derivation and before the registration checks, so both the default and an explicit fresh `parent` succeed on a first run; verify with a provision into a non-existent nested parent
- [ ] 1.3 Update the module header comment, the `ProvisionOptions.parent` doc, and the environment note (git, gh, and now `.ptah/worktree/` ignored) to describe the new default and the `git clean -fdx` trade-off

## 2. Contract and reference consumer

- [ ] 2.1 Apply the delta: sync `openspec/specs/playbooks/spec.md`'s Worktree lifecycle requirement per the change's delta spec (via the sync-specs workflow at verify time, or by hand at apply time as the workflow directs)
- [ ] 2.2 Add `.ptah/worktree/` to this repository's `.gitignore` and confirm `git status` stays clean with a default provisioned worktree present
- [ ] 2.3 Update `std/README.md`'s `worktree.luau` entry (default location, ignore-rule environment requirement, migration note for consumers with existing sibling worktrees — how to retire them with `git worktree remove`/`prune`)

## 3. In-repo consumers and verification

- [ ] 3.1 Update `.ptah/workflows/factory/main.luau` comments that describe the worktree path ("sibling of the repo root … outside any checkout") to the new default; behavior of `prepareWorktree`/teardown calls unchanged — verify with `ptah check .ptah/workflows/factory/main.luau`
- [ ] 3.2 Extend `.work/worktree-verify.luau` with a default-parent case (provision without `parent` against the throwaway repo: path is `<MAIN>/.ptah/worktree/main-<name>`, parent auto-created, adoption and teardown behave as before); run `ptah run .work/worktree-verify.luau` and confirm every check passes
- [ ] 3.3 Run `openspec validate --change worktree-default-under-ptah --strict` and confirm zero issues
