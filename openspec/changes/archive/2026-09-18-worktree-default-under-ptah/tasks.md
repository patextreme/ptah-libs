# Tasks — worktree-default-under-ptah

## 1. Library mechanism (`std/worktree.luau`)

- [x] 1.1 Change the default `parent` to `{root}/.ptah/worktree` (keep the `<parent>/<repo-basename>-<name>` derivation); verify by reading the derived path in a scratch provision against this repo
- [x] 1.2 Create the resolved parent directory (`mkdir -p` via `ptah.exec`) after path derivation and before the registration checks, so the creation SHALL holds by the library's own act rather than git's version-dependent native parent creation; verify by inspection that the exec precedes the registration checks — a black-box provision into a missing nested parent cannot distinguish this change (current git creates nested parents natively)
- [x] 1.3 Update the module header comment, the `ProvisionOptions.parent` doc, and the environment note (git, gh, and now `.ptah/worktree/` ignored) to describe the new default and the `git clean -ffdx` trade-off
- [x] 1.4 Prune a stale registration (a registered worktree whose directory was deleted out-of-band — `git clean -ffdx`, a manual `rm`) before the adopt check, so adoption never returns a nonexistent path; the worktree is re-created at the same path from the surviving branch (D5) — verify in the harness by deleting the directory out-of-band and re-provisioning

## 2. Contract and reference consumer

- [x] 2.1 Apply the delta: sync `openspec/specs/playbooks/spec.md`'s Worktree lifecycle requirement per the change's delta spec (via the sync-specs workflow at verify time, or by hand at apply time as the workflow directs)
- [x] 2.2 Add `.ptah/worktree/` to this repository's `.gitignore` and confirm `git status` stays clean with a default provisioned worktree present
- [x] 2.3 Update `std/README.md`'s `worktree.luau` entry (default location, ignore-rule environment requirement, migration note for consumers with existing sibling worktrees — how to retire them with `git worktree remove`/`prune`)

## 3. In-repo consumers and verification

- [x] 3.1 Update `.ptah/workflows/factory/main.luau` comments that describe the worktree path ("sibling of the repo root … outside any checkout") to the new default; behavior of `prepareWorktree`/teardown calls unchanged — verify with `ptah check .ptah/workflows/factory/main.luau`
- [x] 3.2 Create `.work/worktree-verify.luau` (uncommitted scratch, per the `.work/` convention — the file does not exist yet): port the prior worktree change's inline cases (fresh provision, adopt-as-is, fast-forward, diverge-errors; teardown clean, dirty refusal, branch survival — all passing `parent` explicitly, expected unaffected) and add the default-parent case (provision without `parent` against the throwaway repo: path is `<MAIN>/.ptah/worktree/main-<name>`, parent auto-created, adoption and teardown behave as before); run `ptah run .work/worktree-verify.luau` and confirm every check passes
- [x] 3.3 Run `openspec validate --change worktree-default-under-ptah --strict` and confirm zero issues
