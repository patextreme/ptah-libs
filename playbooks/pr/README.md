# pr playbook

Two operations over one shared review-pass atom, against a pull request:
`review` runs **exactly one review pass** and never fixes; `reviewFixLoop`
runs the convergent review→validate→fix→verify loop. In both, an agent
reviews the PR freely in prose following a reviewer persona and a **typed
judge** converts that prose into structured findings reconciled with a
persistent **ledger**. Neither operation **asks a human**: the pull request
itself, reviewed by its human at merge time, is the human checkpoint.
Extracted and generalized from identus-ws's pr-review-loop; the facade split
is decided in [ADR 0007](../../docs/adr/0007-review-pass-vs-review-fix-loop.md).

**`review` — the pass.** Exactly one review pass: discovery (a full-PR
review) when no ledger exists, a delta review otherwise — **unconditionally**:
no ledger state gates or skips it (a pass against an already-reviewed head
still runs; deleting the ledger is the documented re-review escape hatch).
The pass never fixes, commits, or pushes: it persists the ledger, posts the
report, and returns its outcome. A CI-triggered single review, or a
read-the-report-first workflow, is what this verb is for.

**`reviewFixLoop` — the loop.** The loop is *convergent*, not symmetric: the
first pass reviews the whole PR (discovery); every later pass reviews only
the changes since the ledger's last-reviewed commit; convergence is computed
from typed data (`no open blocking findings` — plus, when the
[check gate](#the-check-gate-loop-only-off-by-default) is configured, green
checks at the PR head), never parsed from prose; and a fix is issued only
when budget remains, so **every push is followed by at least one review
pass** — the loop cannot exit having just mutated the PR.

## Phase shape

Both operations run the same pass shape; the loop composes it with fix turns
and a budget:

- **Discovery** — a PR with no ledger gets one full-PR review. Its result
  creates the ledger with the discovery SHA, the PR's intention, and the
  typed findings.
- **Delta review** — every later review pass carries the ledger's
  `lastReviewedSha` and directs the reviewer to review only the changes since
  that commit and to report recurrences by ledger finding id.
- **Judge** — the work session reviews in prose; a judge session created with
  a `resultSchema` receives the prose, the ledger (open **and** deferred
  findings with their ids), the PR's intention, and the configured
  `blockingAdditions`, and returns typed findings (severity, family,
  validation status, `needsHuman`) plus a reconciliation of the ledger's open
  and deferred findings — resolved (with evidence), still open, or still
  deferred. A recurrence of a deferred finding is reported against that
  finding's id as still deferred, never refiled as a duplicate.
- **Converge and report** — when the judge reports no open blocking
  findings, the loop closes the review session, the **reporter agent**
  authors the PR review report, and the playbook prepends a deterministic
  status line and posts the marked report comment (edited in place across
  runs). See [The PR review report](#the-pr-review-report).
- **Fix** — when open blocking findings remain and budget remains, one batched
  fix turn addresses all of them by root cause, followed by commit-and-push
  (gated by `dryRun`). An open blocking finding carrying the judge's
  `needsHuman` flag is fixed autonomously like any other blocking finding —
  the flag is report-only, so nothing interrupts the loop (see
  [needsHuman is report-only](#needshuman-is-report-only-the-pr-is-the-human-checkpoint)).
- **Cap** — a single `maxIterations` (default 10). At the cap with open
  findings the loop ends and returns a non-converged outcome **without
  fixing** — the final unit is always a review. (The default moved from 8
  when the check gate landed: check-fix cycles consume loop units like
  review-fix cycles. Consumers wanting the old cap set it explicitly —
  see [Migration notes](#migration-notes-the-facade-split-pass-vs-loop).)

## The instruction contract (three layers)

The playbook's instruction contract has three layers, so either operation's
structure never depends on the quality or format of a repo-authored
instruction:

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
playbook**, not an instruction swap: operation shape is playbook policy. The
boundary around deterministic signals is drawn precisely: **executing repo
gate commands** (running the repository's own build/lint/test tooling) is
outside the playbook forever — that is the work session's job during a fix
turn — while **reading the platform's check state** joins the loop only
through the [check gate](#the-check-gate-loop-only-off-by-default), when that
gate is configured. With the gate off, check state is invisible to the loop
and post-loop policy remains the calling script's responsibility. This
reversal is recorded in [ADR
0008](../../docs/adr/0008-review-loop-gates-on-check-state.md).

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

## The check gate (loop-only, off by default)

The loop's convergence criterion gains a second signal when the `checks`
config is present: GitHub's own verdict on the PR head. Converged comes to
mean **ledger-clean and checks-green at one head SHA**. The knob is
loop-only — like `dryRun` and `maxIterations` — and inert for `review`,
which runs one pass and has no convergence decision to gate. With the table
absent the gate is off: no check state is read, no check finding exists, and
the loop's behavior is unchanged (one deliberate exception: the
`maxIterations` default moved 8 → 10 — see [the cap note](#phase-shape) and
the migration notes).

```lua
checks = {
	scope = "required",       -- "required": only checks the repository requires;
	                          -- "all": the whole status rollup counts
	pollBudgetMs = 1_800_000, -- per gate consult, 30 minutes
	pollIntervalMs = 30_000,  -- poll spacing while checks run
},
```

**One atomic read.** A single GraphQL query returns the head SHA, the status
rollup, and per-check required-ness together, so the head cannot move
between the SHA read and the state read. Checks classify **green**
(`SUCCESS`, `NEUTRAL`, `SKIPPED`; commit-status `SUCCESS`), **red**
(`FAILURE`, `TIMED_OUT`, `CANCELLED`, `STARTUP_FAILURE`; commit-status
`FAILURE`/`ERROR`), or **pending** (`QUEUED`, `IN_PROGRESS`, `PENDING`, and
`STALE` — a run for a superseded commit carries no verdict about the head;
any state not named green or red — e.g. a run awaiting maintainer approval —
is pending too, since the check has produced no verdict). An **empty in-scope
set is vacuously green**: a repository with no checks, or (under
`scope = "required"`) branch protection that requires none, gets no special
handling — the repository's branch-protection configuration is the
repository's responsibility. Under `"required"`, only checks GitHub reports
as required count; a required check that has never started is invisible to
the rollup and therefore degrades to vacuous green — an accepted limitation,
not solved with a branch-protection API join. A rollup larger than the
100-context page cap logs a truncation line and classifies the first page
only.

**Two consult flavors, three consult points.**

- **Gate consult** (polls within the budget) — at exactly the places the
  loop can end converged: the mid-loop exit after a judge-clean pass, and
  the resume clean-at-head fast path. Green converges; red files check
  findings and falls through to the existing fix-turn/cap logic; still
  pending at budget exhaustion ends the loop **non-converged with a named
  pending outcome** — never a hang, never a silent pass: the status line
  names the pending checks and the outcome's `checks.state` is `"pending"`.
  Recovery is structural — the next run's resume fast path re-polls, and
  time has passed.
- **Snapshot consult** (one read, no wait) — at the resume-with-open-blockers
  fast path, so its fix turn batches check findings with review findings and
  a check a human fixed out of band closes before the turn runs.
- **Terminal read** — one non-waiting consult at every terminal outcome that
  did not just decide convergence at the same head, retried twice on
  transport failure, then degrading to `checks.state = "unknown"` with a
  logged line: finished work never fails over a reporting read. A consult
  failure at a decision point, by contrast, fails the operation through the
  transport's error path (resumable; the ledger persists at each phase).

Polling happens only at convergence decisions (review-clean) — a wait
anywhere else is waste: after a push the checks restart from scratch, and
during a fix turn the upcoming pass provides latency overlap. The same
decision point is what picks up a fix-turn regression: a pushed fix that
breaks a check is observed at the next pass's convergence decision, which
files the check finding and loops it through the fix machinery — external
CI is not the first to see the regression.

**Red checks become ledger findings, not a wait.** A failing check files a
playbook-owned **check finding**: blocking, `needsHuman` false, family
`check`, validation `validated`, `source: "check"`, title
`CI check "cargo" failing (run: <url>)` — a pointer, not a diagnosis; the
fix session investigates from the run URL itself, and the playbook executes
no repo gate commands. Identity is **one open finding per failing check
name**: red while a finding is open updates the run URL in place (same id);
a green rollup at head closes **every** open check finding (`fixed`,
resolved count advanced — the all-close rule means a check that leaves the
gate's scope never orphans a finding); a re-failure after a green close
files a new finding. Check findings count toward the open blocking count,
drive fix turns, and receive fixing commits like any open blocker — and the
judge is blind to them: the ledger view the judge reconciles excludes check
findings, and a reconciliation record naming one is inert on it. The judge's
prose never saw check state, so it can never classify them.

**Budget arithmetic.** The poll budget is **per gate consult**, not per
operation: iterations are already bounded by `maxIterations`, so the
worst-case wall clock is `maxIterations × pollBudgetMs` — with the defaults,
10 × 30 min = 5 h on a pathological PR. Real, bounded, documented, and both
knobs are consumer-tunable. Check-fix cycles consume `maxIterations` units
like review-fix cycles — there is no separate budget; on the final unit a
judge-clean pass with a red check ends non-converged with the finding open,
and no fix is issued that no review would follow.

**Dry-run interaction (honesty over ergonomics).** With `dryRun`, no push
means no re-run: a red check can never close, and the loop ends
non-converged at the cap with the finding open. That is dryRun's contract —
don't pretend — so it is documented rather than special-cased. Pending
checks on the existing head still complete and can converge; nothing about
dryRun blocks the wait.

## The ledger

The playbook's state lives in a **dedicated PR comment** marked
`<!-- ptah:pr-review-ledger -->`, updated in place through the `gh` transport.
It carries the PR identity, the discovery SHA and the `lastReviewedSha`, the
PR's intention, the findings (id, one-line title, family, severity, validation
status, the judge's `needsHuman` determination, status
`open`/`fixed`/`deferred`/`accepted`, source `review`/`check` with the check
name for check findings, fixing commit), the family table, and
the resolved count.

- **Auto-resume, no flag.** A fresh `reviewFixLoop()` against a PR whose
  ledger comment exists resumes from it: open blocking findings drive a fix
  turn; a clean ledger at the current head converges immediately. A finding
  carrying `needsHuman` drives the fix turn like any other open blocking
  finding — the flag is the reviewer's pointer, not a gate. The `review`
  operation takes no resume path at all: it runs its single pass
  unconditionally — discovery when no ledger exists, a delta review
  otherwise — regardless of ledger state.
- **`needsHuman`.** Each finding carries the judge's latest
  `needsHuman` determination: recorded when the finding is filed, updated
  when a later reconciliation revisits it, and never cleared — there is no
  mid-loop human decision to supersede it. The flag is report-only: it never
  gates, pauses, or fails the loop, and the report renders it on open
  findings' lines. A ledger written before the flag existed reads tolerantly
  (a finding without the flag is treated as not needing a human) and the flag
  is written on the next persist. Ledgers from the retired ask path may carry
  a **decisions record**: read tolerantly, ignored, and dropped on the next
  persist — no new decisions are ever recorded.
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
- **Check findings.** The check gate (below) is a finding writer alongside
  filing, reconciliation, and verification: a red check files a blocking
  finding with `source: "check"` and the check name, red-while-open updates
  it in place, a green rollup at head closes every open check finding, and
  a re-failure after a green close files a new finding. The judge never
  sees them: the ledger view the judge reconciles excludes check findings,
  and a reconciliation record naming one is inert on it. A ledger written
  before the `source` field existed reads tolerantly (findings without it
  are review-sourced) and the field is written on the next persist.
- **One operation per PR.** Two concurrent operations on one PR corrupt the
  in-place comment update; one operation per PR at a time is an environment
  requirement, not a locked invariant — a lone `review` pass corrupts
  in-place comment writes exactly like a loop.

The PR's intention is captured at discovery from the PR title and body; when
the body is absent it falls back to the last commit message before the first
ledger record. Later passes reuse the cached intention; the judge never
re-fetches it.

## The PR review report

Every terminal outcome that *returns* — from either operation, converged or
non-converged — produces a **PR review report**: a human-facing summary of
the PR review operation (one review pass or a whole loop), posted as a
dedicated PR comment marked `<!-- ptah:pr-review-report -->` and **edited in
place** across runs (the same marker-and-edit lifecycle as the ledger, so a
re-run of either operation edits rather than appends). A run that *fails* —
reporter exhaustion — raises and posts no report.

The report is authored by a dedicated **reporter agent** (`reporterAgent`,
required; `reporterSessionConfig` optional). The reporter submits a typed
single-field result (the report body), bounded-retried exactly as the judge
is; exhaustion fails the operation with an error naming the reporter and the
attempt count — never a silent absence of the report. The converged work
session does **not** author or post the report.

The playbook prepends a **deterministic status line** — the outcome status and
the count of open blocking findings, read from the ledger, plus the checks
verdict when the operation ran with the check gate configured (`; checks
green`, `; checks red: cargo`, `; checks pending: cargo`, or `; checks
unknown`) — so the report's convergence claim is never agent-authored. With
the gate off the line is byte-identical to the ungated form. The reporter
authors the body under a fixed section contract:

- *What this PR does* — the PR's intention.
- *Findings resolved* — one line per resolved finding, capped at the 50 most
  recent with an "…and N earlier omitted" note (the ledger retains every
  entry).
- *Open non-blocking*, *Deferred*, *Accepted* — one line per finding.
- *Review summary* — the pass count (1 for a lone `review` pass; the loop's
  completed units for `reviewFixLoop`), the discovery and last-reviewed
  commits, and the family table.
- *Open blocking* — for a non-converged outcome only, leading the body.

The reporter session receives the full ledger (every status group, including
retained `fixed` entries), the terminal status, and the section contract, plus
the last review pass's prose when the current operation ran one. A resume that
converges immediately, or that ends at the cap without a new review pass, has
no prose, so the prompt carries an explicit no-prose marker and the report is
rendered from the ledger alone; a `review` pass always runs, so its report
always carries the prose. `outcome.report` carries the posted text
(status line plus body), so a caller can display the report without re-reading
the PR; `outcome.verdict` is the pass prose for `review` (the pass always
runs) and the final verdict text for `reviewFixLoop` (empty only on the
resume fast paths that run no pass).

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
- **One operation per PR** — one operation (a lone `review` pass or a whole
  `reviewFixLoop`) per PR at a time; see [The ledger](#the-ledger).
- **Repo gate commands stay out; platform check state comes in only through
  the gate** — the playbook never executes the repository's own verification
  tooling (that is the work session's job during a fix turn, forever out;
  see [ADR 0008](../../docs/adr/0008-review-loop-gates-on-check-state.md)).
  Reading GitHub's check state happens only when the
  [check gate](#the-check-gate-loop-only-off-by-default) is configured, and
  only in the loop: with the gate off (or for `review`), check state is
  invisible to the playbook and post-loop policy remains the calling
  script's job.

## Coverage contract

This library ships no test suite: the ptah repository's offline suite owns
updated coverage for this playbook — the pass entry point (`review` as one
unconditional pass that never fixes), the loop's byte-stable sequence through
the shared pass primitive, and the consolidated ask-retirement pins (no ask
is raised; flagged findings drive fix turns like any other blocking
finding).

## needsHuman is report-only (the PR is the human checkpoint)

Neither operation asks a human at any point, and ask-provider availability is
irrelevant — a provider-less environment behaves identically to a served one.
The judge's `needsHuman` flag is **report-only**: the judge sets it only on an
open blocking finding that rests on an operator-owned decision — one the agent
has no authority to take — that a human should examine at review, and never on
a deferred or non-blocking finding. The flag persists in the ledger, renders
on the finding's line in the PR review report (`, needs human`), and never
gates, pauses, or fails the loop: an open blocking finding carrying it is fixed
autonomously like any other blocking finding, and the next review pass re-judges
the fix. A reconciliation record carrying the determination for an id absent
from the ledger has no loop effect.

Human decisions land at PR review time — the merge review, guided by the
report's flags — never in the ledger mid-run. A human who disagrees with a
run's direction lets it finish (or kills it) and rules at review time; the
loop never fails on human refusal because there is no ask to refuse.

Whether an ask *would* be served is moot: no ask is raised, so the operator's
provider selection (`--ask` > `PTAH_ASK` > `[ask]` > TTY auto-detect) plays no
part in this playbook.

## Config (data plus declared agent handles)

```lua
local pr = require("./luau_packages/ptah_libs").pr

local ops = pr.new({
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
	dryRun = false,                      -- reviewFixLoop only: never push
	                                     -- (default false; inert for review)
	maxIterations = 10,                  -- reviewFixLoop only: cap
	                                     -- (default 10; inert for review)
	-- reviewFixLoop only: the check gate. Nil keeps it off (no check state
	-- is read, no check findings exist); inert for review.
	-- checks = {
	-- 	scope = "required",       -- or "all"
	-- 	pollBudgetMs = 1_800_000, -- per gate consult
	-- 	pollIntervalMs = 30_000,  -- poll spacing
	-- },
})
```

Session-config entries (`{ id, value }`, applied in declared array
order — see the library README's [Session config](../../README.md#session-config)
section) reach: `sessionConfig` → each review/fix work session;
`judgeSessionConfig` → every judge session;
`reporterSessionConfig` → every reporter session. Option ids are
agent-specific — enumerate what your agent offers with `session:configOptions()`.
The removed `model`/`judgeModel` fields are nil-typed: configuring one is a
`ptah check` type error naming the field.

`workingDir` is an **absolute** directory that receives **every** session
the playbook creates — each review/fix work session, every judge session,
and every reporter session — so no session of the loop can read or write
the wrong tree. Nil (the default) keeps today's behavior byte-for-byte:
sessions run in the invocation directory. The playbook is **git-agnostic**:
it declares no worktree field and never provisions or tears one down — the
field is just a directory, and pointing it at one produced by
`std.worktree` (or a plain clone) is the calling shim's business. Pass an
absolute path; a relative one is not resolved by the playbook.

`judgeAgent` is **required and load-bearing**: the outcome status of either
operation is computed from the judge's typed output, and there is no
prose-parsing fallback. A judge that never submits a typed result is retried
a bounded number of times; exhaustion fails the operation (never a silent
converge, no fix prompt issued).

## Operations

- `ops:review(prUrl)` — run **exactly one review pass** against one pull
  request; the PR URL is per-call data and the sole repository context.
  Unconditional: discovery when no ledger exists, a delta review otherwise;
  no ledger state gates or skips it. Never fixes, commits, or pushes. Returns
  a **typed outcome**:

  ```lua
  { status = "converged" | "non-converged", verdict = "<pass prose>", ledger = { ... }, report = "<posted report text>", checks = nil }
  ```

  `verdict` is always the pass prose; `status` is `converged` when no open
  blocking findings remain after the pass, `non-converged` otherwise. The
  report posts on every return. `checks` is always nil here — the knob is
  loop-only.
- `ops:reviewFixLoop(prUrl)` — run the convergent review→fix loop: passes
  composed with batched fix turns under `maxIterations`, resuming from an
  existing ledger automatically, never asking. Same outcome shape;
  `verdict` is the final verdict text (empty only on the resume fast paths
  that run no pass). The outcome additionally carries `checks` — the check
  gate's terminal snapshot `{ state = "green" | "red" | "pending" | "off" |
  "unknown", failing = { ... }, pending = { ... } }` — always present for
  the loop (`"off"` when the gate is unconfigured), nil from `review`.

  Outcomes as data, so the caller's script can gate its own post-operation
  steps (CI, gates) on the operation's end state. `report` is the exact text
  posted as the PR review report (status line plus body). The returned
  status is always `converged` or `non-converged` — neither operation asks,
  so no escalation failure exists, and reporter exhaustion is the only
  failure that raises.

With `dryRun = true` the loop's commit-and-push step is skipped entirely: the
loop still reviews, judges, and fixes, but never pushes to the PR branch — a
gate for rehearsing persona changes against a real reviewer without pushing.
The report is still posted: dry-run gates the branch, not the PR conversation.
The knob is loop-only — inert for `review`, which never pushes.

The playbook ships facade-only (`:review`, `:reviewFixLoop`). A `run()` daemon
convenience (looping over open PRs) was deliberately deferred: it is sugar
over `std.daemon` + `:reviewFixLoop` and can be added without breaking the
facade.

## Migration notes (the check gate: maxIterations default 8 → 10)

The `maxIterations` default moved 8 → 10: check-fix cycles consume loop
units like review-fix cycles, so the old default starved the loop one unit
sooner on gated repos. **This is the one deliberate gate-off behavior
change.** Consumers wanting the old cap set `maxIterations = 8` explicitly —
the field is unchanged, only the default moved. The check gate itself is
off by default; nothing else changes until a consumer configures `checks`
(see [The check gate](#the-check-gate-loop-only-off-by-default)).

## Migration notes (the facade split: pass vs loop)

This is a breaking reshape. **Lead warning — the silent shrink: an old shim
calling `:review` still runs, and silently stops fixing.** The `review` verb
now means exactly one review pass; a consumer that wanted the convergent loop
must rename the call to `:reviewFixLoop`. Making `review` fix again is the
bug, not the repair
(see [ADR 0007](../../docs/adr/0007-review-pass-vs-review-fix-loop.md)).

- **`review()` is repurposed** — one unconditional review pass (discovery
  when no ledger exists, a delta review otherwise), never fixing, committing,
  or pushing, reporting on every call. Consumers running loops: rename
  `:review(prUrl)` → `:reviewFixLoop(prUrl)`.
- **No alias, no flag** — the clean break is the repo's ritual; pin the prior
  tag to defer (rollback is the same pin).
- **Loop behavior is unchanged except the report's summary section** —
  "Loop summary" is renamed "Review summary" and carries a pass count
  instead of the iteration count; resume fast paths, fix turns, the budget
  rule, and never-ask behavior are byte-stable.
- **`dryRun` and `maxIterations` are loop-only** — inert for `review`.

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
  capped). Read `outcome.report` for the posted text. A failed run (reporter
  exhaustion) raises and posts no report.
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
- **The escalation probe wording changes** — there is no probe session and,
  since the ask's retirement, no trigger either: the judge's `needsHuman`
  flag is report-only and the loop raises no ask
  (see [needsHuman is report-only](#needshuman-is-report-only-the-pr-is-the-human-checkpoint)).
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
  `pr-review:` error prefixes, and the session-id prefixes stay
  byte-stable — in-flight ledgers and existing PR comments are not orphaned.

The previous export name remains at the prior tag; consumers pin it to defer
the break.
