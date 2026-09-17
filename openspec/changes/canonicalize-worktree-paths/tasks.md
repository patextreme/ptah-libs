## 1. Lossless worktree inventory

- [ ] 1.1 Separate raw Git stdout from the existing trimmed text path in `std/worktree.luau`, keeping current callers unchanged while allowing inventory output to retain NUL delimiters and path whitespace; verify with `ptah check` and a scratch exec that round-trips embedded NUL output.
- [ ] 1.2 Change worktree discovery to `git worktree list --porcelain -z` and parse NUL-delimited fields into exact path/branch records, treating a record without `branch refs/heads/...` as detached; verify against worktrees whose paths contain spaces, non-ASCII characters, quotes or backslashes, and a newline.

## 2. Canonical provision path

- [ ] 2.1 Add physical parent resolution that interprets a relative `parent` from the selected repository root, preserves absolute-parent behavior, shell-quotes every dynamic value, and fails loudly when the parent is absent; verify root and subdirectory invocations return the same physical absolute target.
- [ ] 2.2 Derive one target from the physical parent and use it for inventory lookup, existence checks, Git arguments, errors, and adoption results; verify calling provision twice with a relative parent adopts the original worktree and preserves dirty state.
- [ ] 2.3 Re-read the inventory after `git worktree add`, require the expected physical target to be registered on the requested branch, and return Git's exact path key; verify fresh provision through a symlinked parent returns the physical path and a rerun through the alias adopts it.
- [ ] 2.4 Preserve rejection behavior while changing path identity: verify wrong-branch and detached registrations raise without mutation, and a non-empty unregistered directory remains untouched and is rejected.

## 3. Documentation

- [ ] 3.1 Update `std/worktree.luau` comments and `ProvisionOptions.parent` documentation to state that relative parents resolve from the selected repository root and provision returns Git's canonical physical absolute path; verify the comments match the delta spec.
- [ ] 3.2 Update `std/README.md` only where needed to document relative-parent and canonical-return behavior without changing the current default-parent policy; verify no issue #21 default or parent-creation behavior is presented as already available.

## 4. Integrated verification and change hygiene

- [ ] 4.1 Extend or recreate the ignored `.work/worktree-verify.luau` scratch harness with relative-parent, subdirectory, absolute-parent, symlink, unusual-path, dirty-adoption, wrong-branch, detached, and unrelated-directory cases; run it with `ptah run` and confirm every assertion passes without adding a shipped test suite.
- [ ] 4.2 Re-run the existing fresh-create, fast-forward, divergence, surviving-branch resume, clean teardown, dirty refusal, and forced-teardown checks to confirm path canonicalization did not change lifecycle policy; verify the full scratch harness passes.
- [ ] 4.3 Run `ptah check` for the affected Luau module or its scratch consumer and `openspec validate --change canonicalize-worktree-paths --strict`; resolve every finding and confirm both commands succeed.
