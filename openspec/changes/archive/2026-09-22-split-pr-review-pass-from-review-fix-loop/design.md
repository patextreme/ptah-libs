# Design

## Context

`playbooks/pr/playbook.luau` implements the whole convergent loop inside
one `review` closure: resume fast paths, the review-pass sequence (prompt →
work session → judge → `applyFindings` → persist), fix turns, and the
terminal `finish` (reporter + status line + post). The spec delta splits
the contract into a "PR review pass" requirement and a "PR review-fix loop"
requirement; operation semantics were settled in a grilling session and
recorded in `docs/adr/0007-review-pass-vs-review-fix-loop.md` and the
`CONTEXT.md` glossary (both already on this branch). See proposal.md for
motivation.

## Goals / Non-Goals

**Goals:**

- One extracted review-pass primitive shared by both operations, so the
  ledger/judge/reporter logic cannot drift between them.
- `reviewFixLoop` is behaviorally byte-stable except the section-contract
  rename ("Loop summary" → "Review summary").
- `review` is one unconditional pass — no resume fast paths, no fix.

**Non-Goals:**

- A `run()` daemon convenience over the facade (still deliberately
  deferred).
- Per-pass report comments (in-place editing kept for both verbs).
- A skip fast path for the pass on a reviewed head (rejected — see ADR).
- Per-verb config surfaces (one shared `Config`; a consumer wanting
  different agents per verb constructs two instances).

## Decisions

- **Extract, don't nest.** `review` is *not* `reviewFixLoop` with
  `maxIterations = 1`: the loop's resume fast paths (fix-turn-first,
  clean-at-head converge) and no-fix-on-final-unit rule make a one-unit
  loop semantically different from a pass. Instead the review-pass
  sequence becomes a closure inside `M.new` (over `prUrl`, `ledger`,
  `commentId`, `persist`, returning verdict + outcome status), called once
  by `review` and once per unit by the loop. *Alternative considered:*
  nesting — rejected above.

- **Outcome type shared verbatim.** `review` returns the existing
  `Outcome` (`status`/`verdict`/`ledger`/`report`). No new type, no new
  status vocabulary. `verdict` is always the pass prose (the `""` case
  only ever arose from the loop's fast paths).

- **Pass prompt header.** The loop prepends
  `[pr-review iteration N of M]`; the pass has no budget, so it prepends
  `[pr-review pass]`. *Alternative:* no header at all — rejected; the
  header is how the agent's transcript shows what invoked it.

- **Session ids stay in the `pr-review` family.** Work session
  `pr-review-pass`, judge session `pr-review-pass-judge`, reporter session
  unchanged (`pr-review-reporter`). The frozen elements stay frozen: PR
  comment markers, `pr-review:` error prefixes, and existing session-id
  prefixes (ADR 0001's wire-freeze rule). The pass adds new ids; it
  renames none.

- **Pass count replaces iterations in the report.** `sectionContract` and
  the reporter prompt's summary section become operation-agnostic: the
  "Review summary" section carries a pass count — 1 for `review`, the
  loop's completed units for `reviewFixLoop`. `statusLine`,
  `postReport`, and the marker-and-edit lifecycle are untouched.

- **Config doc comments mark loop-only knobs.** `dryRun` and
  `maxIterations` doc comments state "reviewFixLoop only — inert for
  `review`" (the instruction-contract requirement's config-surface
  scenario). No config shape change.

- **Consolidated adjudication-retirement scenarios.** The removed
  requirement's six ask-retirement pins collapse into two scenarios
  ("The loop never asks", "Human decision reaches the ledger only at
  review time") carrying the same normative content. The ptah repo's
  offline suite retains the behavioral pins.

## Risks / Trade-offs

- [Silent break: old shims calling `:review` still run but stop fixing] →
  migration note leads the README's breaking-reshape section; ADR 0007
  records the trap ("making `review` fix again is the bug"); consumers pin
  the prior tag.
- [Machinery drift between the two operations] → single extracted
  primitive; the ptah repo's offline suite exercises both entry points
  against the mock agent.
- [Unconditional pass on an unchanged head wastes an agent pass] →
  accepted (the contract stays one sentence); ledger deletion is the
  documented re-review escape hatch.
- [ADR 0006 numbering collides with the `0006` in the landed
  `add-factory-playbook` change] → resolved: that change landed first, so
  this change renumbers its ADR to 0007.
- [Spec consolidation drops a regression pin] → mitigated above; the
  removed scenarios' content is restated, not deleted.

## Migration Plan

1. Land this change as a breaking release; no alias.
2. Consumers running loops update their shim: `:review(prUrl)` →
   `:reviewFixLoop(prUrl)`; pin the prior tag to defer.
3. Rollback: pin the prior tag (the repo's established ritual).

## Open Questions

None — the grilling session settled operation semantics, naming,
breakage posture, config shape, report lifecycle, and concurrency wording
(see issue #34 and ADR 0007).
