# Name playbooks for the entity they manage

Playbooks were first named by capability (`pr-review-loop`). We moved the
surface to entity naming — `pr`, `issue`, `openspec` — with each playbook a
facade of that entity's verbs (`pr:review`, `issue:pickUp`), so a new operation joins an existing facade instead of
spawning a new capability-named playbook. The rename is a clean break (no
export alias), but persisted wire markers (`<!-- ptah:pr-review-ledger -->`,
`<!-- ptah:pr-review-report -->`) stay byte-stable: they are state on
third-party infrastructure, and renaming them would orphan every in-flight
ledger to a fresh discovery pass.

Rejected: capability names (an operation-first name forces a new playbook
per workflow) and a compat alias (two rounds of spec churn to retire it).
