# Proposal: convergent pr-review-loop

## Why

The pr-review-loop playbook diverges structurally on large PRs, as post-mortemed in
[ptah-libs#2](https://github.com/patextreme/ptah-libs/issues/2) (compact#70: 8 rounds /
10h50m / 12 self-generated commits, final head never re-reviewed). The causes are loop
structure, not reviewer quality: no cross-round memory (refuted findings resurface, fixed
families get re-found one variant at a time), full-PR rediscovery every round, per-example
fixes, agent-claimed escalation, and a cap that can end the loop right after a mutation.
The typed machinery to fix this (`resultSchema` sessions, `std/escalate`, `std/gh`) already
exists in the stdlib.

## What Changes

- **BREAKING**: Replace the symmetric review→fix→push iteration with a convergent shape:
  review (full once, then delta-only against the ledger's `lastReviewedSha`) → in-session
  validation subagents → typed judge → converge, fix+push, or end.
- **BREAKING**: The judge becomes the schema boundary. The work session reviews freely in
  prose; a judge session (typed `resultSchema`) converts the prose into structured findings,
  reconciles them with the ledger, steers relevance against the PR's intention, flags
  `needsHuman`, and its typed output is the convergence data (`openBlocking == 0`).
- **BREAKING**: Persistent ledger as a dedicated PR comment (`<!-- ptah:pr-review-ledger -->`),
  updated in place: findings with validation verdicts and status (`fixed` / `deferred` /
  `accepted`), families, `discoverySha`, `lastReviewedSha`, PR intention. A fresh
  `loop:review()` resumes automatically from an existing ledger (no resume flag). Resolved
  findings compact to a count once verified clean in a later epoch.
- **BREAKING**: Single convergence cap `maxIterations` (default 8). A fix+push is issued only
  when open blocking findings exist and budget remains; at the cap with open findings the loop
  ends and returns a non-converged typed outcome — it never fixes on the last unit, so every
  push is followed by at least one review pass.
- **BREAKING**: Instruction contract reshaped into three layers: persona
  (`reviewInstruction`, repo-authored, no classification duties), protocol (hardcoded append,
  never configurable away: delta rules, in-session validation directive, ledger recurrence
  reporting, family reuse), taxonomy
  (judge + new `blockingAdditions` config data). The default instruction drops its
  classification directive.
- **`:review` returns a typed outcome** (status `converged` / `non-converged`, verdict
  text, ledger snapshot) instead of a bare verdict string, matching the stdlib's
  outcomes-as-data convention. Escalation failures do not appear as a status: an
  aborted or unservable ask raises, and an answered ask continues the loop.
- **Out of scope (declared non-goals)**: CI check reading/`waitForChecks`, configured gates,
  closure-audit mode, computed escalation tables. Deterministic signals and post-loop policy
  are the caller's script's job. Escalation has exactly one in-loop trigger: the judge's
  `needsHuman` flag, routed through `std/escalate` (`ptah.ask`) with its existing
  respond/abort/unavailable semantics.
- **BREAKING**: config fields `maxIterations` default changes 15 → 8; `judgeAgent` stays
  required (load-bearing); no new knobs beyond `blockingAdditions`.

## Capabilities

### New Capabilities

- (none — this evolves the existing `playbooks` capability in place)

### Modified Capabilities

- `playbooks`: The pr-review-loop requirements change substantially — loop shape (convergent
  phases replacing symmetric iterations), judge-as-schema-boundary typed findings, PR-comment
  ledger with auto-resume, cap semantics (fix only when budget remains), the three-layer
  instruction contract (persona / protocol append / judge-owned taxonomy), and the typed
  return outcome. Also the library-overview requirement's export surface is unchanged, but
  several pr-review-loop requirement paragraphs (escalation probe wording, classification
  contract, full-replacement instruction semantics) are rewritten.

## Impact

- `playbooks/pr-review-loop/playbook.luau` — rewritten around the phase shape, judge-typed
  results, ledger read/write via `std/gh`, auto-resume, cap semantics, typed return outcome.
- `playbooks/pr-review-loop/default-instruction.luau` — persona updated: classification
  directive dropped, ledger-recurrence and family-reuse guidance moved to the protocol.
- New protocol instruction fragment (component-owned, appended at runtime).
- `playbooks/pr-review-loop/README.md` — contract section rewritten (persona/protocol/
  taxonomy), phase machine, ledger, environment requirements (one loop per PR; `gh` for
  PR host), migration notes.
- Known consumer (identus-ws lineage) must migrate: `maxIterations` default change, judge
  required, `blockingAdditions` replacing per-instruction classification.
- No stdlib changes expected; uses existing `std/predicate` retry pattern, `std/escalate`,
  `std/gh`, `std/session-config`.
- **Out of scope (decided during implementation):** the offline test-suite extension
  for the new behavior. The library's suite lives in the ptah repository and this
  change ships no tests; extending it (phase machine, judge typed findings, ledger
  compaction, cap semantics) is tracked by the ptah-side adoption change.