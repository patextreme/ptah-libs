# playbooks

One directory per workflow playbook: `playbooks/<name>/` holds the
facade module `playbook.luau` (exposing `new(config) -> instance`;
config is data plus declared ptah runtime handles) and the playbook's
README with its declared
environment requirements; a directory may also ship data-only
sibling modules the playbook's contract needs as content (e.g.
`pr/default-instruction.luau`, the built-in reviewer
instruction, and `pr/protocol.luau`, the component-owned
protocol fragment — content, not logic). The module file is `playbook.luau` — not
`init.luau` — so ptah's require resolver and luau-lsp's resolve the
module's internal `../../std/…` requires identically. See
`../README.md` for the full contract.

- `openspec/` — groom, implement, verify an openspec change
- `pr/` — two operations over one review-pass atom on a pull request:
  `review` (one unconditional pass, never fixes) and `reviewFixLoop`
  (the convergent review→validate→fix→verify loop)
- `issue/` — agent-free issue pickup: scan a queue label and claim the
  oldest eligible issue (earliest-claim marker protocol)
- `factory/` — the composition playbook: drains the labeled issue queue
  into reviewed pull requests, composing the three playbooks above
  (constructed internally from its data-only config; ships the agent-free
  `initLabels` label alignment and the canonical default vocabulary)

Both convergence-loop playbooks share one escalation bar: an ask is
justified only by an operator-owned decision — one the agent has no
authority to take and the loop cannot reverse at bounded cost;
confirmations and recoverable choices never ask. The `openspec`
playbook escalates through the stdlib's `escalate` transport when its
probe confirms such a decision — an answered ask resumes the loop, a
refused or unservable ask fails the operation (see `../README.md` for
the loop conventions and each playbook's README for its escalation
behavior). The `pr` playbook never asks: the PR itself, reviewed by its
human at merge time, is its checkpoint, and the judge's `needsHuman`
flag is report-only. The `issue` playbook is agent-free: it creates no
sessions, ships no judge, and asks nothing — the claim protocol is pure
`gh` transport.
