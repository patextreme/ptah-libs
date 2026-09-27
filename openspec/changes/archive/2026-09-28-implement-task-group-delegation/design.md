# Design

## Context

`playbooks/openspec/playbook.luau` composes every work prompt in `drive()`
and appends one component-owned constant there (`AUTONOMY_CLAUSE`). The two
`implement` prompt strings are built inline in the `implement` operation: a
scoped branch (`scope ~= nil`) and a scopeless branch (`scope == nil`). There
is no configurable persona and no protocol-fragment module for this playbook —
unlike `playbooks/pr/`, which keeps a separate `protocol.luau` because its
review prompt has a configurable persona the fragment must survive.

See `proposal.md - Why` for motivation; the spec delta for the contract.

## Goals / Non-Goals

**Goals:**

- Push per-group implementation work out of the orchestrating work session's
  context without changing any observable loop mechanic.
- Keep the delegation directive component-owned (not configurable away) and
  scoped to the scopeless branch only.
- Let an agent without subagent support keep working unchanged.

**Non-Goals:**

- No fork of the `openspec-apply-change` skill; the directive lives in the
  playbook prompt.
- No change to scoped implement runs, groom, verify, the judge, the escalation
  path, or the config type.
- No playbook-level task fan-out (`ptah.parallel` over tasks): the playbook
  cannot see tasks, and the work agent owns delegation.
- No hard subagent environment requirement.

## Decisions

### D1: Discretionary, default-to-delegate (C2) — not mandatory, not hard-verified

The clause directs delegating **by default**, with an explicit escape hatch
("implement directly only when delegation would cost more than it saves"),
rather than mandating one subagent per task (C1) or requiring the orchestrator
to hard-verify each result before flipping checkboxes (C3). Rationale: a
mandatory directive is brittle against agents without subagents and against
tiny changes, while C3 adds friction disproportionate to a prompt-only change.
The cost of discretion is a weaker guarantee; the clause mitigates it by
requiring each group's outcome and evidence in the final report.
*Alternatives:* C1 (mandatory, strongest context win, most brittle); C3 (hard
verification, stronger judge signal, more friction).

### D2: Delegation unit is the task group, not the task

One subagent per top-level number (`1.1, 1.2, 1.3` → one; `2.1, 2.2, 2.3,
2.4` → another). Rationale: tasks under one heading are a coherent unit of
work with shared context, so batching them amortizes subagent setup and keeps
related edits in one place; per-task delegation would spawn a subagent per
checkbox. This matches the existing `"task group 1"` vocabulary the README
already uses for task scopes. *Alternatives:* one subagent per task (more
context isolation, more overhead); agent-chosen grouping (no stable unit).

### D3: Scopeless branch only

The clause is appended only in the `scope == nil` prompt. Rationale: a scope
already narrows the job, and confining the change keeps scoped runs
byte-identical and avoids touching the scoped prompt/accepted-predicate paths.
*Alternatives:* all implement runs (broader benefit, larger spec and regression
surface — rejected by the operator).

### D4: A component-owned inline constant, not a new fragment module

Add a `DELEGATION_CLAUSE` constant beside `AUTONOMY_CLAUSE` and append it in
the scopeless branch. Rationale: the openspec playbook has no configurable
persona, so there is nothing for the clause to survive; an inline constant
matches the established style and is the smallest change. *Alternatives:* a
`playbooks/openspec/protocol.luau` data module mirroring the pr playbook
(deferred until a persona exists; would be premature structure today).

### D5: Orchestrator owns `tasks.md`; verification is a soft obligation

The work session stays the sole writer of the tasks file, and the clause
requires each group's outcome and evidence in the final report. Rationale:
subagents do not run the apply-skill checkbox loop, so there is no concurrent
write race, and the judge — which sees only the orchestrator's prose — gets
each group's outcome carried into it. *Alternatives:* subagents edit
`tasks.md` directly (races); the playbook verifies files itself (out of scope —
the playbook cannot see tasks).

### D6: Subagent support is optional

The directive is phrased so an agent that cannot spawn subagents simply
implements directly; no README "must spawn subagents" requirement is added.
Rationale: delegation is an optimization, so capability gaps degrade to
today's behavior rather than failing the run. *Alternatives:* a hard declared
requirement like the pr playbook's (would fail capable-but-subagentless
agents).

## Risks / Trade-offs

- **The directive is ignored (C2 never fires).** → Default-to-delegate framing
  lowers the threshold, but the outcome stays correct if it does not fire
  (direct implementation). Accepted: context concision is best-effort.
- **Orchestrator trusts unverified subagent summaries.** → The clause requires
  evidence in each group's report and a result check before marking tasks
  complete. The judge-blindness itself is pre-existing, not introduced here.
- **Groups are sequential phases; parallel dispatch risks overlapping edits.**
  → The clause directs running groups one at a time unless they are clearly
  independent. This is prompt content, not a new spec constraint.
- **The clause reads as conflicting with the apply skill's per-task loop.** →
  Frame delegation as the mechanism of that loop, not a replacement: the
  orchestrator still marks task checkboxes and reports status per the skill.
- **Clause drift from the spec.** → The spec delta names the clause's required
  elements (default-to-delegate, per-group, concise report, orchestrator as
  sole writer); `tasks.md` verifies the prompt against them.

## Migration Plan

Prompt-only: no config, API, or data changes, so no consumer migration. Rollback
is removing the clause and the constant.

## Open Questions

- Exact clause wording is deferred to implementation; the spec fixes its
  required elements, not its prose.
