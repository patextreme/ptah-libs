# issueWorker meta playbook

Take one GitHub issue from pickup to a reviewed, CI-green pull request by
composing the stdlib, other playbooks, and deterministic stages. One
run processes at most one issue and leaves nothing running between
runs. The deterministic mechanics — worktree and branch invariants,
delivery re-checks, the label lifecycle, and all bookkeeping — belong to
the playbook; agent handles and repo shape arrive as config data.

This is a **meta playbook**: it composes `std` helpers, the `openspec`
and `prReviewLoop` playbooks, and the `ciGate` playbook, plus its own
deterministic git/`gh` stages.

## Environment requirements (declared, not bundled)

The playbook installs none of these itself. Before running, verify the
environment provides:

- **Agent registry handle(s)** — the `agent` / `judgeAgent` /
  `reporterAgent` handles you construct (e.g. `ptah.agent("pi")`) must
  exist in the consumer's registry and be able to read and write the
  repository. `agent` drives triage, direct implementation, and
  delivery, and is forwarded to every nested playbook as the work
  handle; `judgeAgent` must be able to answer typed-result prompts;
  `reporterAgent` authors the PR review report.
- **`gh` rights** — the authenticated user needs rights to **label**,
  **assign**, **comment**, and **create pull requests** in the target
  repository. The playbook creates the ready and blocked labels
  idempotently, claims issues by assignment, comments the paper trail,
  and re-checks/edits the delivered PR's title.
- **`git` with commit signing** — commits are made by the agent with the
  configured `commitSignArgs` (e.g. `{ "-S", "-s" }` for DCO), so signing
  must work headlessly. The playbook itself fetches, creates/reuses the
  worktree, merges the base branch, and counts commits ahead.
- **`openspec` on PATH only when the route is enabled** — with
  `openspec = true`, triage offers the openspec route and the nested
  openspec playbook drives the `openspec` CLI and its skills; with the
  flag off (the default), the run requires no openspec environment at
  all.
- **A gitignored `worktreeDir`** — `worktreeDir` defaults to `"tmp"`
  relative to the repository root, and **the consumer is responsible for
  gitignoring it**. The playbook creates per-issue worktrees there and
  never writes inside the library tree.

## Config (data plus declared agent handles)

```lua
local issueWorker = require("./luau_packages/ptah_libs").issueWorker

local worker = issueWorker.new({
	agent = ptah.agent("pi"),          -- work handle (own stages + nested work)
	judgeAgent = ptah.agent("pi"),     -- nested openspec / PR-review judges
	reporterAgent = ptah.agent("pi"),  -- nested PR review report body

	sessionConfig = { { id = "model", value = "claude-opus-4-5" } },
	judgeSessionConfig = { { id = "model", value = "claude-haiku-4-5" } },
	reporterSessionConfig = { { id = "model", value = "claude-opus-4-5" } },

	-- Required repo shape (the library ships no default label):
	readyLabel = "ai-r4d",
	blockedLabel = "ai-blocked",
	baseBranch = "develop",
	branchPrefix = "issue-",
	gateCommands = { "just lint", "just test-fast" },

	-- Defaulted:
	worktreeDir = "tmp",               -- consumer must gitignore
	commitTypes = { "feat", "fix", "chore", "docs", "refactor", "test", "build", "ci", "perf", "revert" },
	commitSignArgs = { "-S", "-s" },
	pickupLimit = 30,
	maxAttempts = 3,
	reviewMaxIterations = 5,
	ciTimeoutSeconds = 3600,
	ciPollSeconds = 30,
	ciRepairAttempts = 3,
	openspec = false,

	-- Optional repository prose injected into every stage prompt
	-- (triage, direct implementation, delivery):
	repoBrief = "Follow AGENTS.md. This environment runs inside nix develop.",
})
```

Every role handle is wrapped once per issue with
`std.agent.inDirectory(handle, worktree)` before use, so every session —
the playbook's own stages and those of the nested playbooks — runs in
the per-issue worktree, and no stage sets `cwd`.

Session-config entries (`{ id, value }`, applied in declared array
order — see the library README's [Session
config](../../README.md#session-config) section): `sessionConfig` drives
the playbook's own stages and is forwarded as the work config to every
nested playbook; `judgeSessionConfig` reaches the nested openspec and
PR-review-loop judges; `reporterSessionConfig` reaches the nested PR
review loop's reporter.

Functions are not configuration; every field is data or a declared agent
handle.

## Operations

Per-call data is a method argument:

- `worker:run()` — perform pickup and, when an issue is eligible, the
  whole lifecycle. Returns the outcome.
- `worker:pickup()` — ensure the labels, select and claim the oldest
  eligible open issue, and return it (or nil).
- `worker:process(issue)` — run a claimed issue through to delivery or
  rejection, without re-triggering pickup.

## Outcome-as-data boundary

The playbook never calls `ptah.exit` or `ptah.ask`; it records every
stage failure as bookkeeping and returns a typed outcome that the
consumer's shim maps to an exit code:

```lua
{ status = "delivered", issue = issue, prUrl = "https://github.com/o/r/pull/12" }
{ status = "rejected",  issue = issue, reason = "missing acceptance criteria" }
{ status = "idle",      issue = nil }
{ status = "failed",    issue = issue, reason = "issueWorker: branch issue-12 has no commits ahead of origin/develop" }
```

## Lifecycle

1. **Pickup** — ensure the ready and blocked labels idempotently, list
   open issues carrying the ready label oldest-first, and skip an
   already-assigned issue, an issue whose branch already has an open PR,
   and an issue whose branch exists without its worktree. The first
   eligible issue is claimed by assigning the authenticated user; the
   ready label stays on (the assignee is the claim). A claim lost to a
   concurrent run skips the issue.
2. **Worktree** — fetch `origin/<baseBranch>` and create (or reuse) the
   per-issue worktree on `<branchPrefix><number>`.
3. **Triage** — one typed-result session returns a route, rationale, and
   conventional-commit type (and, on the openspec route, a change name).
   An invalid or missing verdict is retried up to `maxAttempts`. Routes:
   `direct` (one session implements and commits), `openspec` (only when
   enabled; the change directory must exist, then the nested openspec
   playbook runs groom → implement → verify), and `reject` (blocked
   bookkeeping, `rejected` outcome).
4. **Delivery** — one typed-result session runs `gateCommands`, merges
   `origin/<baseBranch>` (never rebases), pushes, and opens the PR with
   the composed conventional-commit title. The playbook then
   deterministically re-checks commits-ahead, the URL shape, and the
   title (correcting it through `gh`, or failing).
5. **Review** — the nested `prReviewLoop` runs before CI; a CI repair
   push never re-runs the review. A non-converged review is recorded
   through the failure bookkeeping and returns a `failed` outcome
   (carrying the review verdict) without running the CI gate.
6. **CI gate** — the nested `ciGate` watches the rollup to green. An
   `unresolved` gate records the failure bookkeeping and returns a
   `failed` outcome.

## Bookkeeping

Every GitHub write outside the PR is the playbook's, so every run leaves
the same paper trail:

- **success** — comment the PR URL on the issue; the ready label and
  assignee stay in place.
- **rejection or failure** — comment the reason, swap the ready label
  for the blocked label, and remove the assignee, so a human re-queues
  the issue by swapping the labels back.
