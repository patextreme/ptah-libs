# Proposal

## Why

A scopeless `implement` run drives every pending task of a change through a
single work session, so that session's context accumulates every file read,
edit, and command for the whole change. On a large change this bloats the main
context window, and the agent loses coordination detail exactly when the run
most needs it. The work agent's own subagents already exist as a way to push
per-task execution out of the main context; nothing in the playbook prompt
tells it to use them.

## What Changes

- Add a component-owned **delegation clause** to the **scopeless** implement
  work prompt (`implement(change)` with no scope). The clause directs the work
  agent to delegate implementation by default, one subagent per **task group**
  — the tasks sharing a top-level number in the tasks file (`1.1, 1.2, 1.3` to
  one subagent; `2.1, 2.2, 2.3, 2.4` to another) — passing each subagent its
  group's tasks and the context it needs, and having it return a concise report
  (tasks done, files changed, verification evidence). The orchestrator carries
  each group's outcome into its final report and checks a group's result before
  marking its tasks complete; the loop's judge only sees the orchestrator's
  prose.
- Frame the directive **discretionarily, default-to-delegate** (`C2`):
  implement directly only when delegation would cost more than it saves.
  Delegation is an optimization, not an obligation — an agent that cannot spawn
  subagents keeps working, so subagent support is **not** a new hard
  environment requirement.
- Leave every other mechanic untouched: scoped implement runs stay
  byte-identical, and the judge acceptance, convergence loop, escalation path,
  returned text, and `tasks.md` ownership (the orchestrator is the sole writer)
  are unchanged.
- Document the delegation behavior in the openspec playbook README, and note
  subagent support as an optional work-agent capability.
- Supersede the existing spec scenario "Scopeless implement is unchanged" —
  this change deliberately alters the scopeless prompt — with a delegation
  scenario.

## Capabilities

### New Capabilities

_(none)_

### Modified Capabilities

- `playbooks`: the openspec playbook requirement changes — the scopeless
  implement work prompt now carries a component-owned delegation clause
  (default-to-delegate, one subagent per task group), while scoped runs and all
  other mechanics are unchanged. The "Scopeless implement is unchanged"
  scenario is superseded.

## Impact

- `playbooks/openspec/playbook.luau` — new component-owned clause constant plus
  its append in the scopeless implement prompt branch.
- `playbooks/openspec/README.md` — document the scopeless delegation behavior
  and the optional subagent expectation.
- `openspec/specs/playbooks/spec.md` — delta through this change (not edited
  directly here).
- `CONTEXT.md` — optional "task group" glossary entry to name the delegation
  unit.
- No public API or config type changes, no new config field, no fork of the
  `openspec-apply-change` skill, and no new hard environment requirement.
