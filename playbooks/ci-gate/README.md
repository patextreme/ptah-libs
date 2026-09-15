# ci-gate playbook

Watch a pull request's check rollup to a terminal state and, while
failing checks remain and a repair budget remains, hand the failing
run's logs to a configured agent for a repair push committed with the
configured signing arguments. The `watch` operation returns a typed
outcome instead of raising, so the calling script owns the policy for a
red run.

## Environment requirements (declared, not bundled)

This playbook drives `gh` for the rollup and an agent to author the
repair. Before running, verify the environment provides:

- **`gh` authenticated with check access** — the playbook reads
  `gh pr view <prUrl> --json statusCheckRollup` and, best-effort,
  `gh run view <id> --log-failed` for Actions runs. The `gh` binary must
  be resolvable in the environment the playbook's `ptah.exec` inherits.
- **An agent able to push signed repairs** — the `agent` handle must
  run in the pull request's working tree and be able to commit and push
  to its branch. Because the playbook accepts no `cwd`, a consumer
  running outside a worktree must pin the handle first (e.g.
  `std.agent.inDirectory(agent, dir)`).
- **Git commit signing configured to work headlessly** — when
  `commitSignArgs` carries signing flags (e.g. `{ "-S", "-s" }` for
  DCO), the agent's commit must succeed without an interactive prompt.

The playbook installs none of these itself.

## Config (data plus declared agent handles)

```lua
local ciGate = require("./luau_packages/ptah_libs").ciGate

local gate = ciGate.new({
	agent = ptah.agent("claude"),   -- repair agent handle
	sessionConfig = {               -- optional: applied to every repair session
		{ id = "model", value = "opus" },
	},
	commitSignArgs = { "-S", "-s" }, -- optional: signing args for the repair commit
	timeoutSeconds = 3600,           -- optional: wait budget per push (default 3600)
	pollSeconds = 30,                -- optional: poll interval (default 30)
	repairAttempts = 3,              -- optional: signed repair pushes (default 3)
})
```

Functions are not configuration; every field is data or a declared
agent handle. The playbook accepts no `cwd`: repair sessions run in the
working directory of the supplied `agent` handle.

Session-config entries (`{ id, value }`, applied in declared array
order — see the library README's [Session
config](../../README.md#session-config) section) reach every repair
session. Option ids are agent-specific — enumerate what your agent
offers with `session:configOptions()`.

## Operations

Per-call data is a method argument:

- `gate:watch(prUrl)` — watch the pull request's check rollup to a
  terminal state. Returns the typed outcome (below). A repair push
  restarts the wait budget; the rollup is re-read after each repair.

## Outcome-as-data boundary

`watch` returns a discriminated record and never raises on exhaustion or
timeout:

```lua
{ status = "green", attempts = 0 }
{ status = "unresolved", attempts = 3, reason = "PR checks are red and the 3-attempt repair budget is exhausted" }
{ status = "unresolved", attempts = 0, reason = "PR checks did not settle within the 3600s wait budget" }
```

- `green` — every rollup entry is successful, neutral, or skipped.
- `unresolved` — repair budget exhausted while checks remain red, or the
  checks did not reach a terminal state within the wait budget. The
  caller decides what an unresolved gate means for its run.

The playbook never asks a human: a red check is either agent-fixable or
environmental, and the calling script owns the policy for an unresolved
outcome. A transport failure (for example `gh` unable to read the
rollup) is a loud script error, not a silent `unresolved`.

## Rollup classification

`gh`'s `statusCheckRollup` unions two shapes, and every entry is
classified across all three fields so a pending entry never reads as a
failure and a failing status context never reads as pending:

- **CheckRun** — `conclusion` (`SUCCESS`, `NEUTRAL`, `SKIPPED` pass;
  `FAILURE`, `CANCELLED`, `TIMED_OUT`, `ACTION_REQUIRED`, `STALE`, and
  the other terminal conclusions fail) and `status` (`QUEUED`,
  `IN_PROGRESS`, `PENDING`, `WAITING`, `REQUESTED` are pending).
- **StatusContext** — `state` (`SUCCESS` passes; `PENDING` and
  `EXPECTED` are pending; `FAILURE` and `ERROR` fail).
