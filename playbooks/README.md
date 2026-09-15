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
- `pr/` — convergent review→validate→fix→verify loop on a pull request

Both convergence-loop playbooks escalate to a human through the
stdlib's `escalate` transport when a judged pass cannot proceed — an
answered ask resumes the loop, a refused or unservable ask fails the
operation (see `../README.md` for the loop conventions and each
playbook's README for its escalation behavior).
