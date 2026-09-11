# Design — convergent pr-review-loop

## Context

The playbook today (`playbooks/pr-review-loop/playbook.luau`) is a symmetric
iteration: each loop makes a fresh whole-PR review prompt, asks a one-bit boolean
judge ("verdict contains no blocking issues"), probes for human input with a second
judge, fixes, pushes, and repeats to a cap. Its only cross-round memory is the PR
conversation and git history. The stdlib already provides the machinery this change
builds on: `std/predicate`'s typed-result session pattern (`resultSchema` on session
creation, `promptResult.result`), `std/escalate` (respond/abort/unavailable asks via
an aliased `ptah.ask`), `std/gh` (typed `gh` outcomes), and `std/session-config`.
The motivation and scope are in the proposal; the behavioral contract is the delta
spec. This document covers the how and the decisions behind it.

## Goals / Non-Goals

**Goals:**

- A loop whose convergence is computed from typed data, never parsed from prose.
- Persistent memory across rounds, runs, and machines (the PR itself holds the state).
- A reviewer instruction that can be weak, wrong, or format-free without breaking the
  loop (the judge owns the taxonomy; the loop speaks one vocabulary regardless).
- Structurally impossible end-state: the loop never exits having just mutated the PR
  without a subsequent review pass.

**Non-Goals:**

- Reading CI results, waiting on checks, or executing gate commands — the calling
  script composes those around the playbook.
- Closure-audit mode or any computed escalation table beyond the single `needsHuman`
  trigger.
- Multi-PR orchestration (the `run()` daemon convenience remains deferred).
- Non-GitHub PR hosts (the `gh`-shaped transport is the environment requirement).
- Extending the offline test suite for the new behavior — the suite lives in the ptah
  repository and this change ships no tests; that extension is tracked by the
  ptah-side adoption change.

## Decisions

**D1 — The judge session is the schema boundary; the work session stays prose.**
The work session reviews freely (persona instruction) and submits prose; a judge
session created with a `resultSchema` receives the prose + ledger + intention +
`blockingAdditions` and returns structured findings. *Alternative:* reviewer-side
typed submission (resultSchema on the work session) — rejected because it makes the
loop's convergence sensitive to the repo-authored instruction's compliance; the
compact#70 run showed repo instructions can define neither blocking nor scope. The
judge also retries like `std/predicate` does (bounded attempts, exhaustion fails the
iteration — never a silent converge, never a hang). `judgeAgent` is required and
load-bearing; there is no prose-parsing fallback to fall back *to*.

**D2 — Prompt assembly is four parts, one of them non-removable.** Every review
prompt is: persona (`reviewInstruction` or built-in default, full replacement) +
protocol fragment (component-owned string module; delta rules, in-session validation
directive, recurrence-by-ledger-id, family reuse-or-justify) + phase directive
(discover vs verify) + ledger data
(family names, open findings, `lastReviewedSha`). The protocol append changes the
old "full replacement" contract and is the load-bearing wall: a persona replacement
like compact#70's can no longer strip convergence mechanics.

**D3 — Validation lives in the work session, not in ptah fan-out.** The reviewer
validates its own blocking findings with its in-session subagents; the trigger is a
directive carried by the component-owned protocol fragment (D2), so it cannot be
stripped by a persona replacement and does not depend on the separate probe prompt
that D6 removes. The judge reads the validation outcomes from the prose. *Alternative:* the
script fans out one typed subagent session per finding via `ptah.parallel` — more
deterministic and cacheable, but it doubles ACP session cost and loses the
work-session context; rejected per scope decision. Verdicts are still cached — by
the judge writing validation status into the ledger.

**D4 — Ledger is a PR comment, resumed automatically.** Read-modify-write of a
`<!-- ptah:pr-review-ledger -->` comment via `std/gh` (list comments, find marker,
PATCH). Auto-resume with no flag: the ledger's existence is the resume datum.
*Alternatives:* local state file (dies with the machine, hides state from the human
watching the PR) and an explicit `resume` flag (defends only against hand-edited
ledgers — already out of contract). Compaction: a finding whose fix is verified clean
in a later pass collapses to a resolved count; evidence stays in git history.
Deleted ledger degrades to a fresh discovery pass — today's behavior, acceptable and
documented rather than defended.

**D5 — One cap; fix only when budget remains.** Single `maxIterations` (default 8)
over review passes; a fix turn runs only when the judge reports open blocking
findings *and* budget remains; at the cap the loop returns a non-converged outcome.
*Alternative:* the issue's dual budget (`maxReviewEpochs` + `maxFixTurnsPerEpoch`) —
rejected as two knobs where the phase shape alone guarantees the property that
matters (no fix-then-exit). The family-recurrence table and closure-audit mode from
the issue are dropped entirely: the batched root-cause fix instruction already
covers family repair, and family tracking in the ledger stays informational
(anti-refile).

**D6 — Escalation reuses `std/escalate` verbatim.** The judge's `needsHuman` flag
replaces the two-step probe (work-session probe + boolean human-input judge). One
ask, same prompt-line shape (loop, PR URL, iteration state), full review prose in
details, answer verbatim into the still-open work session, abort and unavailable
keep today's distinct errors. No new transport, no computed escalation table.

**D7 — `:review` returns a typed outcome** (status, verdict text, ledger snapshot)
matching `std/gh`'s and `std/escalate`'s outcomes-as-data convention, so the caller's
script can gate its own post-loop steps (CI, gates) on the loop's end state.

**D8 — Intention source.** PR title/body fetched via `std/gh` at discovery, cached in
the ledger; when the body is absent, the last commit message before the first ledger
record is the intention. Later passes reuse the cached intention; the judge never
re-fetches.

## Risks / Trade-offs

- [Family-string drift across epochs silently disables recurrence tracking] → the
  verify prompt lists the ledger's family names with reuse-or-justify guidance;
  recurrence is informational (no escalation depends on it), so drift costs memory
  quality, not correctness.
- [Judge is a single point of failure (interpretation errors, hallucinated
  reconciliation)] → bounded retries on missing typed result; findings carry
  evidence fields the verdict comment exposes for human audit; `judgeSessionConfig`
  lets consumers pin a stronger model for the judge than the worker.
- [Ledger comment races with a second concurrent loop] → one-loop-per-PR documented
  as an environment requirement; no locking is built.
- [GitHub comment size cap on long PRs] → compaction policy (D4); a still-oversized
  ledger update fails loudly through `std/gh`'s typed outcome rather than truncating.
- [The judge steering findings could suppress real issues] → deferrals are visible:
  ledger `deferred` status plus a deferred list in the verdict comment; a deferred
  finding never blocks convergence but is never hidden either.
- [In-session validation depends on the work agent's subagent capability] →
  declared in the README's environment requirements, as today's probe already
  assumes it.
- [Prompt size: persona + protocol + ledger data on every review pass] → ledger data
  is compacted; persona inlining bounded by the pointer-pattern escape hatch; the
  protocol fragment is fixed-size.

## Migration Plan

1. Evolve the playbook in place; major version bump (pesde tag major).
2. Rewrite `default-instruction.luau`: drop the classification directive; persona
   content otherwise preserved. Add the protocol fragment as a separate module.
3. Rewrite `README.md`: three-layer contract, phase shape, ledger semantics
   (auto-resume, compaction, one-loop-per-PR, playbook-owned), environment
   requirements (`gh`, subagent-capable work agent), out-of-scope boundary (CI,
   gates), migration notes.
4. Migration notes for the known consumer (identus-ws lineage): `maxIterations`
   default 15 → 8 (configurable), `judgeAgent` now required and its judge now
   receives typed resultSchema sessions, new optional `blockingAdditions`, `review`
   returns an outcome object instead of a string, escalation probe wording changes.
5. Offline test coverage stays out of scope: the suite lives in the ptah repository
   and this change ships no tests. Extending it for the new behavior (phase machine,
   judge typed findings and retries, ledger create/read/update/compaction against a
   mocked `gh`, cap semantics, escalation paths) is tracked by the ptah-side adoption
   change; the library's *Offline test coverage* requirement is unchanged.
6. Rollback: the previous playbook shape remains at the prior tag; consumers pin it.

## Open Questions

None. Remaining detail (exact ledger JSON field names, the judge `resultSchema`
shape, prompt wording) is implementation-level and pinned in the tasks.