# std

The repo-agnostic helper layer of Ptah Playbooks — transport, typed
judging, retry, and loop machinery. Knows nothing about any consumer
repo. See `../README.md` for the library contract and consumption model.

- `session-config.luau` — ordered session-config entries applied as
  `setConfig` calls in declared order
- `predicate.luau` — typed boolean judge
- `gh.luau` — GitHub CLI transport (`ptah.exec` + structured outcomes)
- `daemon.luau` — per-repo loop skeleton with error isolation
- `escalate.luau` — best-effort escalation transport over ptah's ask
  facility (outcomes as data; no ask ever raises)
- `worktree.luau` — git worktree lifecycle over `ptah.exec`: `provision`
  (adopt as-is / prune a stale registration and re-create /
  fast-forward-or-fail / create; never reset) and `teardown`
  (refuse-dirty, never branches); an explicit relative `parent`
  resolves from the selected repository root and provision returns
  git's canonical physical absolute path. Worktrees default under
  `<repo-root>/.ptah/worktree/` (pass `parent` to place them elsewhere,
  e.g. outside any checkout); `git` on PATH is a declared environment
  requirement, and so is git-ignoring `.ptah/worktree/` — without the
  rule every default worktree is untracked noise in `git status`, and
  `git clean -ffdx` in the shared checkout deletes the nested worktrees
  (a plain `git clean -fdx` skips nested repositories; branches
  survive; uncommitted state does not; the next provision prunes the
  stale registration and re-creates the worktree, while a locked
  registration raises instead).
  Migrating from the old sibling default (`../<repo>-<name>`): the
  next provision attaches the surviving branch at the new location;
  retire each leftover sibling directory by hand with
  `git worktree remove <old-path> && git worktree prune` (or plain
  `rm -rf` + `prune`)
