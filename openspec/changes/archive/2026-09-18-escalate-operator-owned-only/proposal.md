## Why

The escalation bar is permissive: an ask fires whenever a pass "cannot
proceed without a human" — a bar any cautious agent clears by merely
wanting confirmation, so mechanical choices and approval-to-proceed can
interrupt a human (issue #28; ADR 0005). The pr review loop's ask carries
the additional cost of the trigger, adjudication session, answer grammar,
and decisions ledger machinery that the 2026-09-17 change built — while
the PR itself is already a full human checkpoint at review time. Issue #20
exposed a spec hole in that machinery (the resume fast path bypasses the
`needsHuman` gate entirely), and fixing the hole would mean widening the
machinery rather than questioning it.

## What Changes

- **The bar**: an ask is justified only by an *operator-owned decision* —
  one the agent has no authority to take and the loop cannot reverse at
  bounded cost. Recoverable choices (wrong outcome repaired by judge
  rejection plus one iteration) and confirmations never ask. Product,
  architecture, and scope appear in the prompt copy as examples, not as
  gates.
- **openspec playbook**: mechanism unchanged (judge-rejected pass → probe
  the work session → typed judge against the predicate), with the probe
  prompts and `humanPredicate` strings reworded to the authority bar. A
  component-owned autonomy clause is appended to every work prompt: make
  judgment calls autonomously, note each in the pass output, never wait
  for confirmation.
- **pr playbook**: the ask is retired entirely. Deleted: the escalation
  trigger (`triggeringFindings`' ask role), the ask call and answer
  grammar (`defer <id>` / `accept <id>` / `fix:`), the adjudication
  session and its schema and retries, the decisions ledger record writer
  (legacy ledgers keep tolerant reads), and the abort/unservable ask
  failure paths. An open blocking finding carrying `needsHuman` is fixed
  autonomously like any other blocking finding. **BREAKING** for consumers
  relying on mid-loop asks from the pr loop.
- **`needsHuman` semantics**: unchanged restriction (open + blocking
  findings only) and unchanged report rendering; the flag becomes purely
  a pointer for the human reviewing the PR.
- **Docs**: `CONTEXT.md` gains **Operator-owned decision** and
  **Recoverable choice**, and **Escalation** is rewritten to the authority
  bar (done this session, rides this branch); `docs/adr/0005-escalation-
  gates-on-decision-authority.md` records the decision (done, rides this
  branch).
- Closes #20 by superseding its suggested fix: with no ask in the loop,
  the resume path's auto-fix becomes the specified behavior and the
  "maintainer decision inverted" failure mode is structurally gone.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playbooks`: the openspec playbook requirement's escalation gate is
  reworded to the operator-owned-decision bar (probe and predicate
  semantics, the autonomy clause, a confirmation-never-escalates
  scenario); the PR review loop requirement loses its escalation-trigger,
  adjudication, answer-grammar, and decisions-record requirements and
  gains report-only `needsHuman` semantics (auto-fix, no ask).

## Impact

- `playbooks/openspec/playbook.luau` — probe prompts, predicates, work
  prompt autonomy clause.
- `playbooks/pr/playbook.luau` — deletion of the ask/adjudication
  machinery; judge rule rewording; `judgeSessionConfig` documentation
  loses its adjudication mention.
- `openspec/specs/playbooks/spec.md` — synced at archive time from the
  delta.
- `CONTEXT.md`, `docs/adr/0005-*` — decision record (already written).
- Consumers running the pr loop headless without an ask provider gain
  (asks could previously hard-fail the operation); consumers relying on
  mid-loop human decisions from the pr loop lose them and must move that
  judgment to PR review time, where the report's `needsHuman` flags point
  them.
