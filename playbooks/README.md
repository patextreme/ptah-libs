# playbooks

One directory per workflow playbook: `playbooks/<name>/` holds the
facade module `playbook.luau` (exposing `new(config) -> instance`;
config is data plus declared ptah runtime handles) and the playbook's
README with its declared
environment requirements; a directory may also ship data-only
sibling modules the playbook's contract needs as content (e.g.
`pr-review-loop/default-instruction.luau`, the built-in reviewer
instruction, and `pr-review-loop/protocol.luau`, the component-owned
protocol fragment — content, not logic). The module file is `playbook.luau` — not
`init.luau` — so ptah's require resolver and luau-lsp's resolve the
module's internal `../../std/…` requires identically. See
`../README.md` for the full contract.

- `openspec/` — groom, implement, verify an openspec change
- `pr-review-loop/` — convergent review→validate→fix→verify loop on a pull request
- `ci-gate/` — watch a pull request's check rollup to green, with a bounded
  number of signed repair pushes (typed outcome)
- `issue-worker/` — the meta playbook: one GitHub issue from pickup to a
  reviewed, CI-green pull request, composing `std`, the other playbooks,
  and deterministic stages (private `git.luau` mechanics)

A **meta playbook** composes `std`, other playbooks, and deterministic
stages over a whole unit of work — `issue-worker` is the first. The
convergence-loop playbooks (`openspec`, `pr-review-loop`) escalate to a
human through the stdlib's `escalate` transport when a judged pass cannot
proceed — an answered ask resumes the loop, a refused or unservable ask
fails the operation (see `../README.md` for the loop conventions and each
playbook's README for its escalation behavior). `ci-gate` and
`issue-worker` are outcome-as-data: they return typed outcomes instead of
asking, and the calling script owns the policy.
