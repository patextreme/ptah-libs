# Proposal

## Why

The `pr` playbook ships exactly one operation, `review(prUrl)`, and it *is*
the whole convergent review→fix loop — there is no way to review a PR
without autonomous fixing. A consumer who wants a CI-triggered single
review, or who wants to read the report and decide whether to run the fix
loop, cannot. ADR 0001 (name playbooks for entities) anticipated this: a
new operation joins the existing facade instead of spawning a
capability-named playbook.

## What Changes

- **BREAKING**: the `review` operation is repurposed — it now runs exactly
  **one review pass** (discovery when no ledger exists, delta review
  otherwise) and **never fixes**. An old shim still runs and silently stops
  fixing; consumers pin the prior tag to defer (the repo's ritual; no
  alias).
- **BREAKING**: the convergent loop moves to a new operation name,
  `reviewFixLoop` — behavior unchanged (fix turns, budget, resume fast
  paths, never asks).
- The review pass is the shared atom both operations run: same persona +
  protocol prompt, in-session validation, typed judge conversion +
  reconciliation, `applyFindings`, ledger persist, and reporter +
  deterministic status line. The loop is byte-stable except where noted
  below.
- The pass runs **unconditionally** — no skip fast path when the ledger is
  already reviewed through the current head (the loop keeps its resume fast
  paths; deleting the ledger remains the re-review escape hatch).
- The pass reuses the `Outcome` type and the `converged`/`non-converged`
  vocabulary; `verdict` is always the pass prose.
- The report's section contract renames "Loop summary" → "Review summary"
  (operation-agnostic, carrying a pass count) — a cosmetic change to loop
  reports too.
- The concurrency requirement generalizes from "one loop per PR" to "one
  **operation** per PR at a time": a lone pass corrupts in-place comment
  writes exactly like a loop.
- One shared `Config` serves both operations; `dryRun` and `maxIterations`
  are documented as loop-only (inert for `review`).
- Documentation follows: the library README's export/operation tables, the
  playbook README (operations, migration notes), and the already-landed
  `CONTEXT.md` glossary entries (*Review pass*, *Review-fix loop*,
  *Ledger*) and `docs/adr/0006-review-pass-vs-review-fix-loop.md` on this
  branch.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playbooks`: the "PR review loop playbook" requirement splits into a
  "PR review pass" requirement (the atom, owned by `review`) and a
  "PR review-fix loop" requirement (fix turns, budget, resume fast paths,
  owned by `reviewFixLoop`). The "PR review report", "PR review ledger",
  "PR review instruction contract", and "Playbook working directory"
  requirements reword operation references to cover both verbs; the report
  requirement's summary section renames; the ledger requirement's
  auto-resume paragraph names `reviewFixLoop` and the pass's unconditional
  semantics are stated.

## Impact

- `playbooks/pr/playbook.luau` — the `Instance` type gains `reviewFixLoop`
  and `review` is reimplemented as the single pass; the review-pass
  primitive (prompt → session → judge → applyFindings → persist) is
  extracted once and shared by both operations.
- `playbooks/pr/README.md`, `README.md`, `playbooks/README.md` — operations,
  config knobs per verb, migration notes.
- `openspec/specs/playbooks/spec.md` — via this change's delta.
- Consumers (identus-ws) — breaking: their shim must call `reviewFixLoop`
  for the loop; pinning the prior tag defers the break.
- The ptah repository's offline suite owns updated coverage for the new
  operation (this repo ships no test suite).
- ⚠️ `docs/adr/0006` may collide with the unlanded `0006` in the
  `ptah-libs-issue-32` worktree; whichever lands second renumbers.
