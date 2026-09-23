# ptah-libs

**Ptah Playbooks** — the shared Luau workflow library for
[ptah](https://github.com/patextreme/ptah): repo-agnostic stdlib helpers and
composable workflow playbooks that consumer repositories drive through thin
shims. This repository is the library's home; it is consumed as a **pesde git
dependency pinned to a tag** — never published to a registry. See `CONTEXT.md`
for the vocabulary.

## Consuming

Declare a git dependency on this repository at a tag and install:

```toml
# pesde.toml (consumer)
[dependencies]
ptah_libs = { repo = "https://github.com/patextreme/ptah-libs.git", rev = "v0.1.0" }
```

`pesde install` generates a `luau_packages/ptah_libs.luau` shim in your repo
that requires the package entry and re-exports its values and types. Your
workflow code requires that generated shim — not any deep path into the
library tree (deep-path requires are not a supported surface):

```lua
--!strict
local libs = require("./luau_packages/ptah_libs")

local ops = libs.openspec.new({
	agent = ptah.agent("claude"),
	judgeAgent = ptah.agent("claude"),
	sessionConfig = { { id = "model", value = "claude-opus-4-5" } },
	judgeSessionConfig = { { id = "model", value = "claude-haiku-4-5" } },
})

ops:groom("add-auth")

-- also available:
-- libs.pr.new({ ... })
-- libs.issue.new({ queueLabel = "ready-for-dev", claimedLabel = "in-progress" })
-- libs.factory.new({ queueLabel = "ai-r4d", base = "main" }):drain()
-- libs.factory.initLabels()  -- agent-free label alignment
-- libs.std.predicate.new({ ... })
-- libs.std.gh.run({ ... })
-- libs.std.daemon.run({ ... })
-- libs.std.worktree.provision({ ... }) / libs.std.worktree.teardown(wt)
-- libs.std.sessionConfig.apply(session, entries)
```

## Exports

`lib.luau` returns the library's named camelCase surface, key-for-key:

| Key | Value |
| --- | --- |
| `std.predicate` | typed boolean judge (bounded retry; exhaustion is a script error) |
| `std.gh` | GitHub CLI transport over `ptah.exec` with structured outcomes |
| `std.daemon` | repo loop skeleton with per-repo error isolation |
| `std.sessionConfig` | ordered session-config entries — the shared apply mechanism |
| `std.worktree` | git worktree lifecycle over `ptah.exec`: `provision` (adopt / fast-forward-or-fail / create; never reset) and `teardown` (refuse-dirty; never branches) |
| `openspec` | openspec change playbook (groom, implement, verify) |
| `pr` | PR review playbook — `review` (one unconditional pass, never fixes) + `reviewFixLoop` (the convergent loop) over a typed judge + PR-comment ledger |
| `issue` | agent-free issue pickup (queue-label scan + earliest-claim marker) |
| `factory` | composition playbook (`issueToPR`, `drain`, and the module-level `initLabels` label alignment) — composes the issue, openspec, and pr playbooks and constructs them internally from its data-only config |

Playbooks are constructed with `new(config)`; per-call data (a change name,
a PR URL) is a method argument. See [The playbook
contract](#the-playbook-contract), [Loop
conventions](#loop-conventions), and [Session config](#session-config) below.

A composition playbook constructs its composed playbook instances
internally from its own data-only config: **config carries no playbook
instances** — they are neither data nor ptah runtime handles. The
factory's config is the whole composition flattened (agent handles,
session configs per role, the queue vocabulary, `base`, prompt fragments,
attempt bounds).

### The factory shim: config only

The factory drains a repository's labeled issue queue into reviewed pull
requests — claim the oldest eligible issue, provision its `issue-<n>`
worktree off `origin/<base>`, apply the mapped openspec change or edit
directly, open the issue-linked PR (`Closes #<n>`), run the convergent
review loop, tear down. A consumer shim is config only:

```lua
--!strict
local libs = require("./luau_packages/ptah_libs")

local factory = libs.factory.new({
	agent = ptah.agent("pi"),
	judgeAgent = ptah.agent("pi"),
	reporterAgent = ptah.agent("pi"),
	sessionConfig = { { id = "model", value = "pi/glm-5.3-flash" } },
	queueLabel = "ai-r4d",  -- required, no default: the vocabulary is the repo's
	base = "main",          -- required, no default: the delivery base is the repo's
	conventions = "Read CONTEXT.md first; run the format and test commands before finishing.",
	prContract = "Sign commits (DCO); keep Conventional Commits titles.",
	maxReviewIterations = 10,
})

libs.factory.initLabels() -- optional, module-level: agent-free label alignment (bootstrap/drift repair)
factory:drain()           -- loop issueToPR() until the queue holds no eligible issue
```

See `playbooks/factory/README.md` for the config surface, the outcome
taxonomy, the laws (per-issue error boundary, teardown on the success
path only, non-converged-as-hand-off), and the environment requirements.

## Versioning

- **A tag is a release.** Cut `vX.Y.Z` when you want a consumable revision;
  everything between tags is work-in-progress.
- **During 0.x, breaking changes ship on minor bumps** (`0.1.0` → `0.2.0`
  may remove or reshape exports; patch bumps are fixes only).
- **Minimum ptah per release.** Each release states the minimum ptah
  version it requires, since the library binds to ptah's script surface
  (`ptah.agent`, `ptah.parallel`, `ptah.exec`, `session:setConfig`,
  `configOptions`):

  | ptah_libs | Minimum ptah |
  | --- | --- |
  | 0.1.0 | ptah 0.1.0 (session-config support and `session:sessionId()`) |
  | 0.3.0 | ptah 0.1.0 (no new ptah surface required) |

- **Offline test coverage lives upstream — and is pending.** The library's
  offline suite (mock agent, no network, no real agent) is maintained in the
  [ptah repository](https://github.com/patextreme/ptah); this repo ships no
  tests. At snapshot `6307bd5` ptah has no such suite yet — until it lands,
  the library's regression contract is unbacked, and no tag should be cut.

## Contracts

- **Self-containment** — library modules only require other modules inside
  the tree, never write files inside it, and never depend on a relative
  working directory; the tree works at any install path, including a
  read-only one.
- **Data-only config** — playbook config is data (plus ptah runtime handles
  where a playbook's config type declares them); functions are never
  configuration.
- **`ptah check` is the compatibility gate** — every module is `--!strict`,
  playbooks export their `Config` types, and a consumer's `ptah check`
  validates their shim config against those types when they bump. A removed
  or reshaped field is reported there, not at runtime.
  - *Known interaction with pesde's generated shim:* pesde writes
    `luau_packages/ptah_libs.luau` without a `--!strict` directive, and
    ptah's check pass (as of snapshot `6307bd5`) lints the strict directive
    over the whole literal require graph with no excludes — so a consumer
    shim that goes through the generated shim sees exactly one finding,
    naming that shim file. Types still flow: the analyzer resolves the
    generated shim into the pesde store and validates config against the
    library's exported types (verified by a real `pesde install` of this
    package). The exemption fix belongs to ptah's check pass; until a ptah
    release carries it, treat that single finding as the known shim one.

## Layout

- `lib.luau` — package entry (deliberately not `init.luau`; see the note on
  the luau-lsp quirk under `playbooks/`).
- `std/` — the stdlib: repo-agnostic machinery that knows nothing about
  any consumer repo.
  - `session-config.luau` — ordered session-config entries applied to a
    session as `setConfig` calls (the shared apply mechanism; see
    [Session config](#session-config)).
  - `predicate.luau` — typed boolean judge (asks an agent whether a
    predicate holds for a payload; bounded retry, exhaustion is a script
    error).
  - `gh.luau` — GitHub CLI transport over `ptah.exec` with structured
    outcomes (never raises for a failed command) and POSIX-safe argument
    quoting.
  - `daemon.luau` — repo loop skeleton: apply a per-repo operation with
    per-repo error isolation, sequential or bounded-concurrency parallel.
  - `escalate.luau` — best-effort escalation transport over ptah's ask
    facility: one `ask({ prompt, details? })`, returning `respond`
    (the human's answer), `abort` (the human refused), or
    `unavailable` (the provider's reason) as data — no ask ever
    raises, and no provider needs to be configured.
  - `worktree.luau` — git worktree lifecycle over `ptah.exec`:
    `provision` (adopt as-is / fast-forward-or-fail / create; never
    reset) and `teardown` (refuse-dirty, never branches). `git` on PATH
    is a declared environment requirement.
- `playbooks/<name>/` — one directory per playbook: `playbook.luau` is the
  facade module exposing `new(config) -> instance`, and the sibling
  `README.md` declares the playbook's environment requirements. (The module
  file is `playbook.luau` — not `init.luau` — so ptah's require resolver and
  luau-lsp's agree on the module's internal `../../std/…` requires; an
  `init.luau` module's relative requires resolve one directory off under
  luau-lsp.)
  - `openspec/` — groom, implement, and verify an openspec change.
  - `pr/` — two operations over one review-pass atom against a pull
    request: `review` (one unconditional pass, never fixes) and
    `reviewFixLoop` (the convergent review→validate→fix→verify loop)
    (typed judge, PR-comment ledger; ships the
    built-in persona and the component-owned protocol fragment).
  - `issue/` — agent-free pickup: scan a repo-configured queue label
    and claim the oldest eligible issue with an earliest-wins marker
    comment, returning a typed pickup brief.
  - `factory/` — the composition playbook: drains the labeled issue
    queue into reviewed pull requests by composing the issue, openspec,
    and pr playbooks (constructed internally); ships the canonical
    default label vocabulary and the agent-free `initLabels` alignment.
- `pesde.toml` — package manifest (`luau` target, `lib = "lib.luau"`).
- `CONTEXT.md` — the library's vocabulary.

## The playbook contract

- A playbook is a facade of typed operations: `new(config)` returns an
  instance; instance methods are the operations; per-call data (a change
  name, a PR URL) is a method argument, not config.
- Config is data — strings, numbers, booleans — plus ptah runtime
  handles where the playbook's config type declares them
  (`agent: Agent`). Functions are not configuration.
- Every module is `--!strict` and every playbook exports its `Config`
  type, so a consumer's `ptah check` validates their config against the
  playbook's config type (the compatibility gate).
- Library modules only require other modules inside the tree, never
  write files inside it, and never depend on a relative working
  directory — so the tree works installed anywhere (including a read-only
  nix store path).

## Loop conventions

std ships only mechanisms a third consumer would use verbatim
(transport, typed verdicts, capped retry, isolation) — loop *shape* is
playbook policy, so each playbook writes its convergence loop over
`std/predicate` in exactly the shape its workflow needs. The playbooks'
loops share these conventions, documented here so drift stays visible:

- Sessions: per-iteration work sessions are `<prefix>:<n>` and judge
  sessions `<prefix>-judge:<n>`; a loop that probes for human input
  before asking (openspec) uses escalation-judge sessions
  `<prefix>-escalate-judge:<n>`, while the `pr` playbook creates no
  probe session and raises no ask at all — its `needsHuman` flag is
  report-only.
- Every prompt of a loop is prefixed `[<prefix> iteration N of M]` so
  the agent (and the logs) can see the loop state. A lone operation with no
  budget to count (the pr playbook's `review` pass) is prefixed with its own
  phase header instead (`[pr-review pass]`).
- Escalation is two-mode: **ask when a provider serves the request,
  hard fail when none does.** An ask is justified only by an
  operator-owned decision — one the agent has no authority to take and
  the loop cannot reverse at bounded cost; a confirmation or a
  recoverable choice never asks (the pr playbook never asks at all:
  the PR at merge time is its human checkpoint). A confirmed
  operator-owned decision routes through `std/escalate` — the work
  session stays open across the ask, and a human answer is sent back
  into it verbatim (no header, no framing: the human is driving the
  agent), the iteration counting against the cap like any other. The
  ask's prompt line identifies the operation, the per-call identity,
  and the iteration state (`<prefix> <change or PR URL>: human input
  required (iteration N of M)`); its details carry the work session's
  label and the **full** probe text, untruncated — so the human must be
  able to answer.
- Failure wording: the human refused the ask — `<prefix>: human
  aborted escalation (iteration N of M)`; no provider served the ask —
  each playbook's pre-ask wording, byte-identical, so provider-less
  consumers see zero drift; the cap —
  `<prefix>: did not converge within M iterations` (the `pr` playbook
  instead returns a non-converged typed outcome at its cap, since
  outcomes-as-data is its contract).

### Ask behavior notes

Escalation rides ptah's ask facility, so its behaviors apply. The
provider is the operator's selection — `--ask` > `PTAH_ASK` > project
`[ask]` > user `[ask]` > TTY auto-detect — never script or playbook
config:

- Concurrent asks serialize FIFO, attributed `ask {n} {script}` —
  the ask's identity line is what disambiguates fan-out runs.
- A pending ask keeps the run alive like an outstanding task.
- `--quiet` hides the session stream, but asks always render — and an
  ask carries the full probe text, so it stays self-contained even
  when the stream its session label points at is suppressed.
- There is no ask timeout: an ask blocks until answered, aborted, or
  the run is cancelled (Ctrl-C is run cancellation, exit 130/143 — a
  forgotten terminal parks the run).

Asks display the work session's ptah label (what the run's rendered
stream is keyed by) and the agent-side ACP session id
(`session:sessionId()`) — the id the agent's own tooling can resume or
list — so a human can correlate the ask with the session.

## Worktrees

`std.worktree` is git's worktree lifecycle as transport over
`ptah.exec`: a shim points a playbook at a checkout no other run shares,
without managing git state by hand. It takes no agent handle and no
configuration table, and `git` on PATH is a declared environment
requirement — exactly as `gh` is for the PR transport — and so is a
git-ignored `<repo-root>/.ptah/worktree/`: worktrees default under the
repository's own `.ptah` directory, where the rule keeps them out of
`git status`. A worktree inside the checkout is an accepted trade-off
(`git clean -ffdx` deletes nested worktrees — a plain `git clean -fdx`
skips nested repositories; branches survive, uncommitted state does not,
and the next provision re-creates the worktree from the surviving
branch, while a locked stale registration raises instead) — pass
`parent` explicitly to place worktrees outside every checkout.

```lua
local libs = require("./luau_packages/ptah_libs")

-- One worktree per run, under the repository's own `.ptah/worktree/`.
local wt = libs.std.worktree.provision({
	name = "pr-42",             -- path: <repo root>/.ptah/worktree/<repo>-pr-42
	ref = "origin/fix/login",   -- required; never the shared tree's HEAD
	-- branch defaults to the ref's short name (`fix/login`)
	fetch = true,              -- fetch the ref's remote before resolving
})

-- Every session the playbook creates runs inside it (absolute path).
local loop = libs.pr.new({
	agent = ptah.agent("claude"),
	judgeAgent = ptah.agent("claude"),
	reporterAgent = ptah.agent("claude"),
	workingDir = wt.path,
})

loop:reviewFixLoop("https://github.com/o/r/pull/42")

-- Teardown returns its outcome as data: a dirty refusal is the expected
-- post-crash outcome, so log it and continue rather than failing the run.
local teardown = libs.std.worktree.teardown(wt)
if not teardown.ok then
	ptah.log(`worktree kept at {wt.path}: {teardown.stderr}`)
end
```

A rerun resolves without destroying anything. A registered worktree at
the derived path is **adopted as-is** (branch-verified); an existing
branch whose ref is its remote-tracking counterpart is
**fast-forwarded-or-failed** through `git fetch <remote> <branch>:<branch>`
(a no-op when current, a fast-forward when behind, a loud error when
diverged); any other existing branch is **attached as-is**, preserving a
crashed run's unpushed commits. A failed provision **raises** carrying
git's stderr — the run cannot proceed without a worktree.

`teardown` **refuses a dirty worktree** by default (`force` discards the
changes), then removes and prunes. It never touches branches: unpushed
commits survive on the local branch, and branch deletion is deliberately
outside the API. See the `playbooks` spec's *Worktree lifecycle*
requirement for the full contract.

## Session config

A session-config entry is `{ id: string, value: string | boolean }` —
one `session:setConfig(id, value)` call. A session-config field
(`sessionConfig`, `judgeSessionConfig`, or `std/predicate`'s
`sessionConfig`) takes an ordered *array* of entries, and the array is
the consumer's `setConfig` call sequence as data: entries apply in
declared order after session creation, before the session's first
prompt, via the shared `std/session-config.apply` — the playbooks and
the judge call it so application semantics cannot drift.

- **Order is load-bearing.** Agents with dependent options (opencode
  re-derives `effort` from every `model` set) only behave when the
  driving option is set first — which is why the field is an array, not
  a table.
- **No extra validation.** `nil`/empty applies nothing; duplicate ids
  apply verbatim in order (last wins, exactly as repeated runtime
  `setConfig` calls); an agent-rejected entry fails through the
  existing `setConfig` error path with entries before it left applied.
  Option ids and values are the agent's authority — enumerate them with
  `session:configOptions()`.
- **Mixed string/boolean values in one literal** may need an explicit
  annotation (`local entries: { sessionConfig.Entry } = …`) — the
  analyzer infers one element type per unannotated array literal.

**Migrating from `model`/`judgeModel`** (removed in the same change that
introduced entries — a model choice is an ordinary entry):

```lua
-- before
model = "claude-opus-4-5",
judgeModel = "claude-haiku-4-5",
-- after
sessionConfig = { { id = "model", value = "claude-opus-4-5" } },
judgeSessionConfig = { { id = "model", value = "claude-haiku-4-5" } },
```

`ptah check` names a removed field when you bump — that is the
compatibility gate doing its job.
