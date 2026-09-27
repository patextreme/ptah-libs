# Tasks

## 1. Scopeless delegation clause

- [x] 1.1 Add a component-owned `DELEGATION_CLAUSE` constant to `playbooks/openspec/playbook.luau` (beside `AUTONOMY_CLAUSE`) and append it to the `scope == nil` implement prompt only — verify with `ptah check` on the library and by reading the composed scopeless prompt to confirm the clause is present while the scoped prompt carries no clause
- [x] 1.2 Confirm the clause carries every element the spec delta requires: default-to-delegate with a direct-implementation escape hatch, one subagent per top-level task group, a concise per-group report (tasks done, files changed, verification evidence), the orchestrating session as sole tasks-file writer, groups run one at a time unless clearly independent, and no hard subagent requirement — verify by diffing the clause text against the delta's `openspec playbook` requirement and design D1–D6
- [x] 1.3 Document the scopeless delegation behavior and the optional subagent expectation in `playbooks/openspec/README.md` (implement operation section) — verify the README matches the spec delta and design, and that its environment-requirements list still contains only the existing hard requirements

## 2. Task-group vocabulary

- [x] 2.1 Add a "task group" entry to the `CONTEXT.md` glossary naming the tasks sharing a top-level number as the implementation-delegation unit — verify the entry does not conflict with the existing "Task scope" entry and matches the README's `"task group 1"` usage

## 3. Integration check

- [x] 3.1 Run `ptah check` on the library and `openspec validate implement-task-group-delegation --strict`; then walk the delta's scenarios against the code — scopeless carries the clause, scoped is unchanged and clause-free, and the judge acceptance, escalation path, and returned text are untouched — confirming each scenario has corresponding behavior before archiving
