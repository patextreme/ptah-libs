# pr playbook

Run a convergent review→validate→fix→verify loop against a pull request:
an agent reviews the PR freely in prose following a reviewer persona, a
**typed judge** converts that prose into structured findings and reconciles
them with a persistent **ledger**, and the loop converges, escalates to a
human, or fixes and pushes — then reviews the delta. Extracted and
generalized from identus-ws's pr-review-loop.

The loop is *convergent*, not symmetric: the first pass reviews the whole PR
(discovery); every later pass reviews only the changes since the ledger's
last-reviewed commit; convergence is computed from typed data
(`no open blocking findings`), never parsed from prose; and a fix is issued
only when budget remains, so **every push is followed by at least one review
pass** — the loop cannot exit having just mutated the PR.

## Phase shape

- **Discovery** — a PR with no ledger gets one full-PR review. Its result
  creates the ledger with the discovery SHA, the PR's intention, and the
  typed findings.
- **Delta review** — every later review pass carries the ledger's
  `lastReviewedSha` and directs the reviewer to review only the changes since
  that commit and to report recurrences by ledger finding id.
- **Judge** — the work session reviews in prose; a judge session created with
  a `resultSchema` receives the prose, the ledger, the PR's intention, and the
  configured `blockingAdditions`, and returns typed findings (severity,
  family, validation status, `needsHuman`) plus a reconciliation of the
  ledger's open findings.
- **Converge and report** — when the judge reports no open blocking
  findings, the loop closes the review session, the **reporter agent**
  authors the PR review report, and the playbook prepends a deterministic
  status line and posts the marked report comment (edited in place across
  runs). See [The PR review report](#the-pr-review-report).
- **Fix** — when open blocking findings remain and budget remains, one batched
  fix turn addresses all of them by root cause, followed by commit-and-push
  (gated by `dryRun`).
- **Escalate** — the judge's `needsHuman` flag is the loop's only escalation
  trigger; it routes through the stdlib's `escalate` transport (see below).
- **Cap** — a single `maxIterations` (default 8). At the cap with open
  findings the loop ends and returns a non-converged outcome **without
  fixing** — the final unit is always a review.

## The instruction contract (three layers)

The playbook's instruction contract has three layers, so the loop's structure
never depends on the quality or format of a repo-authored instruction:

1. **Persona** — `reviewInstruction`, repo-authored. A configured value is a
   **full replacement** of the built-in default persona (only a nil value
   selects the default; an empty string stays configured — a loud
   misconfiguration, not a silent fallback). It carries **no classification
   duties**: the reviewer reviews freely in prose.
2. **Protocol** — a component-owned fragment (`protocol.luau`, next to this
   README) appended to **every** review prompt at runtime and **not
   configurable away**: the delta-review rules, the in-session validation
   directive (validate each blocking finding with a subagent before
   finalizing), report-recurrences-by-ledger-id, and family
   reuse-or-justify guidance. A persona replacement cannot strip these
   mechanics.
3. **Taxonomy** — the judge's. What counts as blocking for the repository
   arrives through `blockingAdditions` (free text supplied to the judge),
   never through the reviewer instruction.

Verdicts that do not reduce to a blocking/non-blocking classification — score
gates, approve/request-changes votes, report-only reviews — are a **different
playbook**, not an instruction swap: loop shape is playbook policy.
Deterministic signals (CI checks, configured gates) are **outside** the
playbook — they belong to the calling script, which composes them around
`review()`.

## The built-in default

Leave `reviewInstruction` nil and reviews run against the playbook's built-in
default persona — no instruction to author, no dependency on this
repository's layout. The default (`default-instruction.luau`, next to this
README) is a full reviewer persona with **no classification directive**
(classification belongs to the judge). It is the persona layer's reference
instance — copy it as the worked example when graduating to a configured
instruction.

## The pointer pattern

A long or repo-pinned reviewer instruction is best supplied as text that
references a versioned repository document — one shim line pointing at the
file — rather than inlining the document's content:

```lua
reviewInstruction = "Follow the reviewer instruction at .ptah/instructions/reviewer.md",
```

The playbook treats such text identically to any other (pointer-style text
cannot be reliably detected, so it is never special-cased). The honest trade:
configured text is inlined into every review pass's prompt — fine at the
built-in default's size, and the pointer pattern is the escape hatch for
longer instructions.

## The ledger

The loop's state lives in a **dedicated PR comment** marked
`<!-- ptah:pr-review-ledger -->`, updated in place through the `gh` transport.
It carries the PR identity, the discovery SHA and the `lastReviewedSha`, the
PR's intention, the findings (id, one-line title, family, severity, validation
status, status `open`/`fixed`/`deferred`/`accepted`, fixing commit), the family
table, and the resolved count.

- **Auto-resume, no flag.** A fresh `review()` against a PR whose ledger
  comment exists resumes from it: open blocking findings drive a fix turn; a
  clean ledger at the current head converges immediately.
- **Retention.** Once a finding's fix is verified clean in a later review
  pass, the finding is retained as a terminal one-line entry with status
  `fixed` (id, title, family, fixing commit) and the resolved count
  advances — so the report can list what was fixed. The ledger grows with
  the PR; the report caps its resolved list, and a ledger that outgrows the
  platform comment limit fails loudly through the transport rather than
  truncating.
- **Playbook-owned.** The ledger is the playbook's data. Hand-editing it is
  unsupported, and a deleted ledger degrades a fresh run to a new discovery
  pass (today's per-run behavior) rather than being defended against.
- **One loop per PR.** Two concurrent loops on one PR corrupt the in-place
  comment update; one loop per PR is an environment requirement, not a
  locked invariant.

The PR's intention is captured at discovery from the PR title and body; when
the body is absent it falls back to the last commit message before the first
ledger record. Later passes reuse the cached intention; the judge never
re-fetches it.

## The PR review report

Every terminal outcome that *returns* — converged, or non-converged at the cap
— produces a **PR review report**: a human-facing summary of the whole loop,
posted as a dedicated PR comment marked `<!-- ptah:pr-review-report -->` and
**edited in place** across runs (the same marker-and-edit lifecycle as the
ledger, so a re-run edits rather than appends). A run that *fails* — an
aborted or unservable escalation, or reporter exhaustion — raises and posts no
report.

The report is authored by a dedicated **reporter agent** (`reporterAgent`,
required; `reporterSessionConfig` optional). The reporter submits a typed
single-field result (the report body), bounded-retried exactly as the judge
is; exhaustion fails the operation with an error naming the reporter and the
attempt count — never a silent absence of the report. The converged work
session does **not** author or post the report.

The playbook prepends a **deterministic status line** — the outcome status and
the count of open blocking findings, read from the ledger — so the report's
convergence claim is never agent-authored. The reporter authors the body under
a fixed section contract:

- *What this PR does* — the PR's intention.
- *Findings resolved* — one line per resolved finding, capped at the 50 most
  recent with an "…and N earlier omitted" note (the ledger retains every
  entry).
- *Open non-blocking*, *Deferred*, *Accepted* — one line per finding.
- *Loop summary* — iterations, the discovery and last-reviewed commits, and
  the family table.
- *Open blocking* — for a non-converged outcome only, leading the body.

The reporter session receives the full ledger (every status group, including
retained `fixed` entries), the terminal status, and the section contract, plus
the last review pass's prose when the current operation ran one. A resume that
converges immediately, or that ends at the cap without a new review pass, has
no prose, so the prompt carries an explicit no-prose marker and the report is
rendered from the ledger alone. `outcome.report` carries the posted text
(status line plus body), so a caller can display the report without re-reading
the PR; `outcome.verdict` keeps its meaning (the final review verdict text).

## Environment requirements (declared, not bundled)

- **`gh`-based PR host** — the PR URL must be a GitHub pull request URL, and
  the `gh` CLI must be on the agent's PATH with credentials in the
  subprocess's environment. The ledger is read and written through it.
- **Work agent able to act on the repository and the PR host** — read the
  repo, push commits to the PR branch, and comment on the PR.
- **Work agent able to spawn subagents** — the protocol fragment directs the
  reviewer to validate blocking findings with its own in-session subagents.
- **Judge agent** — any agent that can answer a typed `resultSchema` prompt.
- **Reporter agent** — any agent that can answer a typed `resultSchema`
  prompt; it authors the PR review report body. A weak model is adequate:
  the report is a rendering of typed ledger data plus the deterministic
  status line.
- **One loop per PR** — see [The ledger](#the-ledger).
- **No CI or gate reading** — the playbook never reads check results or
  executes gate commands; that is the calling script's job.

## Config (data plus declared agent handles)

```lua
local pr = require("./luau_packages/ptah_libs").pr

local loop = pr.new({
	agent = ptah.agent("claude"),         -- work agent handle
	judgeAgent = ptah.agent("claude"),    -- required judge agent handle
	reporterAgent = ptah.agent("claude"), -- required reporter agent handle
	sessionConfig = {                     -- optional: applied to every
		{ id = "model", value = "opus" },     -- review/fix session
	},
	judgeSessionConfig = {                -- optional: applied to every judge
		{ id = "model", value = "haiku" },    -- session
	},
	reporterSessionConfig = {             -- optional: applied to every
		{ id = "model", value = "haiku" },    -- reporter session
	},
	-- optional: an absolute directory every session runs in (review/fix,
	-- judge, and reporter alike); nil keeps the invocation directory.
	-- Usually a worktree's path, but the playbook is git-agnostic —
	-- provisioning is the shim's business.
	-- workingDir = "/abs/path/to/checkout",
	-- optional (default when nil: the built-in persona): the persona
	-- layer — the entire reviewer instruction as text, full replacement,
	-- no classification duties. Long or repo-pinned instructions usually
	-- take the pointer pattern:
	-- reviewInstruction = "Follow the reviewer instruction at .ptah/instructions/reviewer.md",
	-- optional: the taxonomy layer — free text supplied to the judge
	-- defining what counts as blocking for this repository.
	-- blockingAdditions = "Only regressions introduced by this PR count as blocking.",
	dryRun = false,                      -- optional: never push (default false)
	maxIterations = 8,                   -- optional: cap (default 8)
})
```

Session-config entries (`{ id, value }`, applied in declared array
order — see the library README's [Session config](../../README.md#session-config)
section) reach: `sessionConfig` → each review/fix work session;
`judgeSessionConfig` → every judge session; `reporterSessionConfig` → every
reporter session. Option ids are agent-specific — enumerate what your agent
offers with `session:configOptions()`. The removed `model`/`judgeModel`
fields are nil-typed: configuring one is a `ptah check` type error naming the
field.

`workingDir` is an **absolute** directory that receives **every** session
the playbook creates — each review/fix work session, every judge session,
and every reporter session — so no session of the loop can read or write
the wrong tree. Nil (the default) keeps today's behavior byte-for-byte:
sessions run in the invocation directory. The playbook is **git-agnostic**:
it declares no worktree field and never provisions or tears one down — the
field is just a directory, and pointing it at one produced by
`std.worktree` (or a plain clone) is the calling shim's business. Pass an
absolute path; a relative one is not resolved by the playbook.

`judgeAgent` is **required and load-bearing**: the loop's convergence is
computed from the judge's typed output, and there is no prose-parsing
fallback. A judge that never submits a typed result is retried a bounded
number of times; exhaustion fails the iteration (never a silent converge, no
fix prompt issued).

## Operations

- `loop:review(prUrl)` — run the loop against one pull request; the PR URL is
  per-call data and the sole repository context. Returns a **typed outcome**:

  ```lua
  { status = "converged" | "non-converged", verdict = "<final verdict text>", ledger = { ... }, report = "<posted report text>" }
  ```

  Outcomes as data, so the caller's script can gate its own post-loop steps
  (CI, gates) on the loop's end state. `report` is the exact text posted as
  the PR review report (status line plus body). Escalation failures do not
  appear in the outcome: an aborted or unservable ask raises, so the returned
  status is always `converged` or `non-converged`.

With `dryRun = true` the commit-and-push step is skipped entirely: the loop
still reviews, judges, and fixes, but never pushes to the PR branch — a gate
for rehearsing persona changes against a real reviewer without pushing. The
report is still posted: dry-run gates the branch, not the PR conversation.

The playbook ships facade-only (`:review`). A `run()` daemon convenience
(looping over open PRs) was deliberately deferred: it is sugar over
`std.daemon` + `:review` and can be added without breaking the facade.

## Escalation (ask when served, fail otherwise)

The judge's `needsHuman` flag is the loop's only escalation trigger (there is
no separate probe session). When flagged, the loop escalates through the
stdlib's `escalate` transport: it pauses on an ask — the work session stays
open — whose prompt line identifies the loop, the PR URL, and the iteration
state (`pr-review https://github.com/o/r/pull/42: human input required
(iteration 2 of 8)`) and whose details carry the work session's label and the
**full** review prose, untruncated, so the human can answer. Three outcomes:

- **respond** — the answer is sent verbatim as the next prompt of the
  still-open work session (no header, no framing: the human is driving the
  agent), and the commit-and-push step follows the human-guided fix exactly as
  it follows any fix (gated by `dryRun`). The iteration counts against the cap
  and the loop continues toward convergence.
- **abort** (the human refused the ask) — the operation fails with
  `pr-review: human aborted escalation (iteration N of M)` and no fix is
  issued.
- **unavailable** (no ask provider served the request: prohibited,
  unconfigured, provider failure, or end of input) — the operation fails with
  the same wording as before asks existed: `pr-review: human input is
  required to resolve the findings (iteration N of M)`.

Whether an ask is served is the operator's provider selection
(`--ask` > `PTAH_ASK` > `[ask]` > TTY auto-detect), never playbook
config — a provider-less environment keeps the pre-ask failure
behavior exactly.

Asks display the work session's ptah label (what the run's rendered
stream is keyed by) and the agent-side ACP session id
(`session:sessionId()`) — the id the agent's own tooling can resume or
list — so a human can correlate the ask with the session.

## Migration notes (identus-ws lineage)

This is a breaking reshape. Every breaking item in the change proposal:

- **`maxIterations` default changes 15 → 8.** Set it explicitly to keep the
  old budget.
- **`judgeAgent` is required and now receives typed `resultSchema` sessions**
  (findings, not booleans). A judge agent that cannot submit a typed result
  fails the iteration after bounded retries.
- **`reporterAgent` is required and `reporterSessionConfig` is new.** The
  report is authored by a dedicated reporter agent; a consumer that does not
  configure one fails `ptah check`.
- **The converged work-session comment is replaced by the PR review
  report.** The converged work session no longer posts a comment; the
  playbook posts the report on every returned terminal outcome (converged and
  capped). Read `outcome.report` for the posted text. A failed run (aborted
  or unservable ask, reporter exhaustion) raises and posts no report.
- **The ledger retains resolved findings** as terminal `fixed` entries
  instead of collapsing them into a count. The report caps its resolved list
  at 50; the ledger grows with the PR.
- **`review()` returns an outcome object, not a bare verdict string.** Read
  `outcome.status`, `outcome.verdict`, `outcome.ledger`, and `outcome.report`
  instead of the returned string.
- **`reviewInstruction` is now the persona layer only.** The built-in default
  no longer carries a classification directive, and a configured instruction
  is no longer asked to classify findings. Move the repository's blocking
  taxonomy into `blockingAdditions`.
- **`blockingAdditions` is new** (optional free text supplied to the judge).
- **The escalation probe wording changes** — there is no probe session; the
  judge's `needsHuman` flag is the trigger. Abort/unavailable error wording is
  unchanged.
- **Loop shape changes** — full discovery once, delta reviews thereafter, a
  persistent ledger comment, and no fix on the final unit.

The previous playbook shape remains at the prior tag; consumers pin it to
roll back.

## Migration notes (export rename to `pr`)

This is a breaking reshape. Every breaking item in the change proposal:

- **The library export `prReviewLoop` becomes `pr`.** The single consumer
  edit is in the shim: `require("./luau_packages/ptah_libs").prReviewLoop` →
  `require("./luau_packages/ptah_libs").pr` (rename the local/field with it).
- **The playbook directory `playbooks/pr-review-loop/` becomes
  `playbooks/pr/`.** Consumers require the generated shim, not a deep path,
  so the directory rename needs no consumer edit.
- **Persisted wire and wording are frozen.** The ledger/report markers
  (`<!-- ptah:pr-review-ledger -->`, `<!-- ptah:pr-review-report -->`), the
  `pr-review:` error/ask prefixes, and the session-id prefixes stay
  byte-stable — in-flight ledgers and existing PR comments are not orphaned.

The previous export name remains at the prior tag; consumers pin it to defer
the break.
