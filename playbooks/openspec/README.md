# openspec playbook

Groom, implement, and verify a named openspec change through a
convergence loop: prompt an agent (running the openspec skills), judge
the output with a typed predicate, fix and repeat until the predicate
holds, a human is needed, or the iteration cap is reached.

## Environment requirements (declared, not bundled)

This playbook drives an agent through the openspec workflow skills and
the `openspec` CLI. Before running, verify the environment provides:

- **Work agent carrying the openspec skills** — the agent you pass
  as `agent` (a handle you construct, e.g. from a registry name or an
  inline agent spec) must have the openspec skill set installed
  (`openspec-review`, `openspec-apply-change`,
  `openspec-verify-change`, and the archive lifecycle) and must be able
  to read and write your repository.
- **`openspec` on PATH** — the agent invokes the `openspec` CLI to read
  change state and to sync/archive; it must be resolvable in the
  environment the agent's subprocess inherits.
- **Judge agent** — any agent that can answer typed boolean prompts
  (a small/fast model is ideal); it needs no openspec skills.

The playbook installs none of these itself.

## Config (data plus declared agent handles)

```lua
local openspec = require("./luau_packages/ptah_libs").openspec

local ops = openspec.new({
	agent = ptah.agent("claude"),       -- work agent handle
	judgeAgent = ptah.agent("claude"),  -- judge agent handle
	sessionConfig = {       -- optional: applied to every work session
		{ id = "model", value = "opus" },
	},
	judgeSessionConfig = {  -- optional: applied to every judge and
		{ id = "model", value = "haiku" },  -- human-probe session
	},
	-- optional: an absolute directory every session runs in (work,
	-- judge, human-probe, and archive alike); nil keeps the invocation
	-- directory. Usually a worktree's path, but the playbook is
	-- git-agnostic — provisioning is the shim's business.
	-- workingDir = "/abs/path/to/checkout",
	maxIterations = 10,     -- optional: convergence cap (default 10)
})
```

Session-config entries (`{ id, value }`, applied in declared array
order — see the library README's [Session config](../../README.md#session-config)
section) reach: `sessionConfig` → every per-iteration work session of
groom, implement, and verify, plus verify's archive session;
`judgeSessionConfig` → every judge and human-escalation-probe session.
Option ids are agent-specific — enumerate what your agent offers with
`session:configOptions()`. The removed `model`/`judgeModel` fields are
nil-typed: configuring one is a `ptah check` type error naming the
field (the migration note in the library README shows the entry form).

`workingDir` is an **absolute** directory that receives **every**
session the playbook creates — each per-iteration work session, every
judge and human-escalation-probe session, and verify's archive session —
so no session of the playbook can read or write the wrong tree. Nil (the
default) keeps today's behavior byte-for-byte: sessions run in the
invocation directory. The playbook is **git-agnostic**: it declares no
worktree field and never provisions or tears one down — the field is
just a directory, and pointing it at one produced by `std.worktree` (or
a plain clone) is the calling shim's business. Pass an absolute path; a
relative one is not resolved by the playbook.

Functions are not configuration; every other field is data or a
declared agent handle.

## Operations

Per-call data is a method argument:

- `ops:groom(change)` — converge the change's proposal through review
  (`openspec-review`); exits when the review carries no blocker
  findings, escalating to a human (see
  [Escalation](#escalation-ask-when-served-fail-otherwise)) or the
  cap otherwise.
- `ops:implement(change)` — drive task execution
  (`openspec-apply-change`) until all tasks of the change are
  implemented. Each pass ends either complete or paused with a stated
  reason, as the skill defines those states: a pause the agent can
  resolve itself (e.g. updating the change's artifacts) is resolved and
  the loop continues; a pause that needs human input escalates — an
  answered ask resumes the loop, otherwise the operation fails (see
  [Escalation](#escalation-ask-when-served-fail-otherwise)).
- `ops:implement(change, scope)` — same loop with a task scope: free
  text describing the subset of the change's tasks the run is
  responsible for (e.g. `"task group 1"`, `"the env-reads tasks"`).
  The work prompt treats the tasks matching the scope as the entire
  job (all other tasks stay pending), and the judge accepts the pass
  when the scoped tasks are implemented — not when the whole change
  is. A scope that matches no tasks ends the pass stating that (the
  agent must not substitute a different subset), which surfaces
  through the human-escalation path — an ask when a provider serves
  it; the operation error otherwise
  ([Escalation](#escalation-ask-when-served-fail-otherwise)). Calling
  without a scope keeps the whole-change behavior byte-for-byte.
- `ops:verify(change)` — converge verification
  (`openspec-verify-change`) until it reports no critical findings or
  warnings, then sync and archive the change in the same operation.

Each operation returns the final accepted review text.

## Escalation (ask when served, fail otherwise)

A judge-confirmed need for human input escalates through the stdlib's
`escalate` transport: the loop pauses on an ask — the work session
stays open — whose prompt line identifies the operation, the change,
and the iteration state (`opsx-groom add-auth: human input
required (iteration 2 of 10)`) and whose details carry the work
session's label and the **full** probe text, untruncated, so the human
can answer. Three outcomes:

- **respond** — the answer is sent verbatim as the next prompt of the
  still-open work session (no header, no framing: the human is
  driving the agent). The iteration counts against the cap and the
  loop continues toward convergence.
- **abort** (the human refused the ask) — the operation fails with
  `opsx-groom|implement|verify: human aborted escalation
  (iteration N of M)` and no fix prompt is issued.
- **unavailable** (no ask provider served the request: prohibited,
  unconfigured, provider failure, or end of input) — the operation
  fails with the same wording as before asks existed:
  `openspec-<op>: human input is required (iteration N of M): <probe
  excerpt>`.

Whether an ask is served is the operator's provider selection
(`--ask` > `PTAH_ASK` > `[ask]` > TTY auto-detect), never playbook
config — a provider-less environment keeps the pre-ask failure
behavior exactly. An unresolvable task scope (a scope matching no
tasks) surfaces through this same path: an ask when a provider
serves it, the operation error otherwise.

Asks display the work session's ptah label (what the run's rendered
stream is keyed by) and the agent-side ACP session id
(`session:sessionId()`) — the id the agent's own tooling can resume or
list — so a human can correlate the ask with the session.
