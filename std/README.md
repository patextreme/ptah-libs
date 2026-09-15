# std

The repo-agnostic helper layer of Ptah Playbooks — transport, typed
judging, retry, and loop machinery. Knows nothing about any consumer
repo. See `../README.md` for the library contract and consumption model.

- `session-config.luau` — ordered session-config entries applied as
  `setConfig` calls in declared order
- `predicate.luau` — typed boolean judge
- `agent.luau` — agent directory scoping (wrap a handle so every session
  runs in a fixed working directory)
- `shell.luau` — exec helpers (two-sided `trim`, POSIX-safe `quote`,
  `mustRun`, `succeeds`, `errorMessage`)
- `gh.luau` — GitHub CLI transport (`ptah.exec` + structured outcomes)
- `daemon.luau` — per-repo loop skeleton with error isolation
- `escalate.luau` — best-effort escalation transport over ptah's ask
  facility (outcomes as data; no ask ever raises)
