## 1. std/worktree module

- [ ] 1.1 Create `std/worktree.luau` with the `Worktree` record type and `provision(opts)`: derive the absolute path (`<parent>/<repo-basename>-<name>`, parent defaulting to the repo root's sibling, repo defaulting to the invocation directory via `git rev-parse --show-toplevel`), optional fetch of the ref's remote, then resolution in order — adopt registered worktree as-is (branch-verified), fast-forward-or-fail existing branch via `git fetch <remote> <branch>:<branch>`, attach as-is to an otherwise-existing branch, or `git worktree add -b <branch> <path> <ref>` — raising with git's stderr on failure. Verify `ptah check` on a scratch shim exercising each branch of the resolution order (fresh, adopt, ff, diverge-errors) against a throwaway local git repo.
- [ ] 1.2 Add `teardown(worktree, opts?)`: refuse-dirty default with `force` override, `git worktree prune` after, branches never touched, outcome returned as `{ ok, stderr? }` data (never raising). Verify by teardown of a clean and a dirty throwaway worktree and asserting both return (not raise), and that the branch survives.

## 2. Judge and playbooks

- [ ] 2.1 Add `cwd: string?` to `std/predicate.luau`'s `PredicateOptions`, forwarded into every judge attempt session's options; nil keeps today's behavior. Verify `ptah check` on the library tree passes.
- [ ] 2.2 Add `workingDir: string?` to the openspec playbook's `Config` and thread it into every session it creates (per-iteration work sessions, judge and escalation-probe predicate calls, the archive session), nil unchanged. Verify by reading each `session(` call site in the playbook reaches the field, and `ptah check` on a configured shim passes.
- [ ] 2.3 Add `workingDir: string?` to the pr playbook's `Config` and thread it into work, judge, and reporter sessions, nil unchanged. Verify by reading each `session(` call site and `ptah check` on a configured shim.
- [ ] 2.4 Export the worktree module as `std.worktree` from `lib.luau`. Verify a shim requiring the package entry reaches `libs.std.worktree.provision` (check passes).

## 3. Documentation

- [ ] 3.1 Root README: add `worktree` to the exports table and `std/` layout entry; add a short worktree pattern section (provision → `workingDir` → teardown, including log-and-continue teardown handling); state the `git`-on-PATH environment requirement. Verify by reading the rendered section against the spec's Worktree lifecycle requirement.
- [ ] 3.2 Both playbook READMEs: document `workingDir` (every session, nil unchanged, absolute), the git-agnostic boundary, and the no-relative-working-directory note. Verify config blocks in both READMEs show the field and match the exported `Config` types.

## 4. Dogfood shims

- [ ] 4.1 Retrofit `.ptah/workflows/adhoc/pr-reviews.luau`: derive each PR's head branch via `gh.run({ "pr", "view", ..., "--json", "headRefName" })`, provision a worktree per PR (`fetch` set), construct the loop with `workingDir`, teardown after each outcome (logging a dirty refusal rather than failing). Verify `ptah check` on the workflow and a dry inspection that no `git checkout` of the shared tree remains.
- [ ] 4.2 Retrofit `.ptah/workflows/adhoc/changes.luau`: drop `landFirst` and branch stacking — provision each discovered change from `origin/main` with an explicit `branch`, run groom/implement/verify with `workingDir`, then commit/push/PR from the worktree and teardown; resume falls out of provision's adopt / fast-forward-or-fail. Verify `ptah check` and that no `git checkout -b`/`git checkout <branch>` of the shared tree remains.

## 5. Change hygiene

- [ ] 5.1 Run `openspec validate --change worktree-aware-playbooks` and fix any findings; confirm the minimum-ptah table in the README needs no bump (session `cwd` and `ptah.exec` are within the currently stated minimum).
