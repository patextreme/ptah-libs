# Design: gate review loop convergence on checks

## Context

See `proposal.md` — Why for the incident and the structural failure. The
relevant current state: `reviewFixLoop` has exactly two places it can end
converged (the mid-loop exit after a judge-clean pass, and the resume
clean-at-head fast path); findings live in a ledger comment with a single
writer path (`applyFindings`); the judge's view of the ledger is
`ledgerSummary`; the status line is composed by the playbook in
`statusLine`; and the spec previously forbade reading CI at all (ADR 0008
records the reversal). `ptah.sleep(ms)` exists; there is no clock, which
shapes the poll design below.

Two facts were verified live against GitHub's GraphQL API during design:
`PullRequest.statusCheckRollup` and `PullRequest.headRefOid` are siblings on
one node, and `CheckRun.isRequired(pullRequestNumber: Int)` exists — so one
atomic query returns head, states, and required-ness.

## Goals / Non-Goals

Goals: a check gate that makes "converged" falsifiable by GitHub's own
signal, routes red checks through the loop's existing fix machinery, bounds
every wait, and changes nothing when off (with one named exception: the
`maxIterations` default).

Non-goals (beyond the proposal's): executing repo gate commands from the
playbook (forever out — the fix *session* runs them); retrying failed checks
by re-running them (only the platform re-runs); coverage of the `review`
operation (no convergence decision to gate); flaky-check mitigation beyond
the normal loop (a flaky red behaves like any red — fix, re-review, and a
passing re-run at head closes the finding); any facade change.

## Decisions

### D1. Checks join the criterion; no separate verb

`reviewFixLoop` gains the gate; there is no `ensureCIChecksPass`-style
operation. Alternatives rejected (ADR 0008 records them): a sequential
checks-only loop makes stale convergence claims against the review loop's
pushes (each push invalidates the other loop's terminal claim), violates
every-push-followed-by-a-pass unless it embeds review passes (at which point
it *is* this loop), and duplicates budget/resume/report machinery on a
second facade verb. Converged becomes a claim about both signals at one head
SHA — irreducibly a single-loop property.

### D2. Two consult flavors, two-plus-one consult points

- **gate consult** (poll within budget): the mid-loop convergence exit and
  the resume clean-at-head fast path — exactly the places the loop can end
  converged.
- **snapshot consult** (single read, no wait): the resume-with-open-blockers
  fast path, so its fix turn batches check findings with review findings and
  a check a human fixed out of band closes before the turn runs; and one
  final read at every terminal outcome, so the report and outcome carry
  check state even when no convergence decision ran.

Polling only at convergence decisions (review-clean) is deliberate: a wait
anywhere else is waste — after a push the checks restart from scratch, and
during a fix turn the upcoming pass provides latency overlap. Cost accepted:
in the coincident case (review blockers *and* red checks on one head) the
review findings fix first and the check finding rides the next cycle, one
extra unit — versus consulting before every fix turn, which multiplies
consult points and waits for state a push is about to invalidate.

### D3. One atomic GraphQL read

```
query($owner:String!,$repo:String!,$number:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      headRefOid
      statusCheckRollup{
        contexts(first:100){
          nodes{
            __typename
            ... on CheckRun { name status conclusion detailsUrl
                               isRequired(pullNumber:$number) }
            ... on StatusContext { context state targetUrl }
          }
        }
      }
    }
  }
}
```

One query for head + states + required-ness eliminates the read-skew race
(head moves between a REST head read and a checks read). `scope = "required"`
filters on `isRequired`; `"all"` takes the rollup as-is and needs no
required-ness. Pagination caps at 100 contexts — a log line notes truncation
(a repo with more is notable, not fatal). Transport errors at a *decision*
point fail the operation through the existing `gh` error path (resumable;
the ledger persists at each phase); the *final reporting* read retries twice
then degrades to `state = "unknown"` with a log — finished work never fails
over a reporting read. The exact field spellings (`detailsUrl` vs
`details_url` through `gh api graphql`, StatusContext coverage) are
confirmed in the implementation's first task against a live PR.

### D4. State classification

| Observed state | Class |
| --- | --- |
| `SUCCESS`, `NEUTRAL`, `SKIPPED`; StatusContext `SUCCESS` | green |
| `FAILURE`, `TIMED_OUT`, `CANCELLED`, `STARTUP_FAILURE`; StatusContext `FAILURE`, `ERROR` | red |
| `QUEUED`, `IN_PROGRESS`, `PENDING`, `STALE`; no rollup entry yet for a required check | pending |
| Empty in-scope set (no checks, or none required) | green (vacuous) |

`STALE` is pending, not red: it is evidence about a dead commit, and
re-runs arrive at the head. An empty required set is the repo's branch
protection configuration — no warning, no error (explicitly rejected in
design review: enforcement is the repo's job). One subtlety deferred to
implementation within D3's first task: whether a *required* check absent
from the rollup entirely (never started) is observable via the rollup alone
— if not, it degrades to vacuous green for `"required"` scope the same as
today, and that is accepted rather than a branch-protection API join.

### D5. Check findings: playbook-owned, judge-blind

`LedgerFinding` gains `source: "review" | "check"` and `check: string?`
(tolerant read: absent → `"review"`, like `needsHuman` before it). A check
finding: `severity = "blocking"`, `needsHuman = false`, `family = "check"`,
`validation = "validated"`, title = `CI check "cargo" failing (run: <url>)`
— a pointer, not a diagnosis; the fix session fetches logs through the run
URL itself (extracting excerpts was rejected: log formats vary per check,
and the playbook cannot validate what it parses).

Identity: **one open finding per failing check name**, keyed by `source` +
`check`. Red while open → update the run URL in place, same id. Green at
head → close *every* open check finding (`fixed`, resolved count advanced)
— the all-close rule means a check that leaves the gate's scope never
orphans a finding. Re-failure after a green close → new finding, new id
(the closed one keeps its fix commit), matching how review findings compact.

Ownership is enforced structurally: `ledgerSummary` (the judge's view)
omits check findings, and `applyFindings` treats reconciliation records
naming a check finding as inert — the judge never saw the id, so any
reference is foreign by construction. `openBlockingCount` and the fix
prompt include them unchanged (they already iterate all blocking findings);
`recordFixCommit` stamps them like any open blocker.

### D6. Poll mechanics — bounded iterations, no clock

`maxPolls = ceil(pollBudgetMs / pollIntervalMs)`; each iteration reads,
breaks on green/red (terminal for that head), else `ptah.sleep(
pollIntervalMs)`. Budget is **per gate consult**, not per operation:
iterations are already bounded by `maxIterations`, so worst-case wall clock
is `maxIterations × pollBudgetMs` (with the new defaults, 10 × 30 min = 5 h
on a pathological PR — real, bounded, documented, consumer-tunable). A
whole-operation budget was rejected: it double-counts the cap and forces
"whose wait was this?" bookkeeping. Defaults: `pollBudgetMs = 1_800_000`,
`pollIntervalMs = 30_000`.

Still pending at exhaustion → non-converged with the named outcome
(`statusLine` appends `; checks pending: <names>`, `Outcome.checks.state =
"pending"`). Recovery is structural: the next run's resume gate consult
re-polls — time has passed, checks complete, it converges.

### D7. Outcome and status line

`Outcome` gains `checks: ChecksSnapshot?` where
`ChecksSnapshot = { state: "green" | "red" | "pending" | "off" | "unknown",
failing: { string }, pending: { string } }`. `reviewFixLoop` always fills
it (`off` when the gate is unconfigured, `unknown` on degraded final read);
`review` returns nil — loop-only, documented like `dryRun` and
`maxIterations`. The status vocabulary stays two-valued (`converged` /
`non-converged`) — the factory gates on it, and the named outcome lives in
the snapshot + status line.

`statusLine` appends the verdict clause only when the gate is configured:
`; checks green` / `; checks red: cargo` / `; checks pending: cargo,
devshell` / `; checks unknown`. Gate off → byte-identical to today's line.
The reporter's section contract is unchanged — check state is
playbook-composed text, never agent-authored.

### D8. Config surface and validation

```lua
checks = {                          -- nil = gate off (default)
    scope = "required" | "all",
    pollBudgetMs = 1_800_000,
    pollIntervalMs = 30_000,
}
```

Validated at `M.new` (scope enum; positive, non-zero numbers; interval ≤
budget) — fail fast on misconfiguration, not mid-loop. `maxIterations`
default moves 8 → 10 globally (the one gate-off behavior change, named in
the migration note); conditional defaults (10 when gated, 8 when not) were
rejected as a knob interaction not worth the criterion-purity.

### D9. dryRun interaction — honesty over ergonomics

With `dryRun`, no push means no re-run: a red check can never close, and the
loop ends non-converged at the cap with the finding open. That is dryRun's
contract (don't pretend), so it is documented rather than special-cased.
Pending checks on the *existing* head still complete and can converge —
nothing about dryRun blocks the wait.

## Risks / Trade-offs

- [GraphQL shape or permissions differ on real PRs] → the first
  implementation task runs the D3 query live against a PR with required
  checks before any loop wiring; `scope = "all"` needs no required-ness and
  is the compatible fallback, but silent scope drift is forbidden — a
  required-ness read failure under `"required"` errors loudly.
- [Long wall clock on pathological PRs (5 h worst case)] → documented
  arithmetic; both knobs are consumer-tunable; pending-at-budget is a named
  outcome, not a hang, so an operator can always re-run.
- [Flaky check burns loop units] → same bounded behavior as a stubborn
  review finding: fix → re-review → cap. A passing re-run at head closes
  the finding with no code special-casing flakiness.
- [Ledger grows with check findings churning red/green] → fixed entries
  compact to one line each as today; a ledger that outgrows the comment
  limit still fails loudly through the transport.
- [Concurrent operations on one PR] → unchanged environment requirement
  (one operation per PR at a time); the gate adds reads, not writers, to
  the comment protocol.

## Migration Plan

1. Land the change with the gate off — behavior identical except
   `maxIterations` default 8 → 10 (migration note: consumers wanting the
   old cap set it explicitly).
2. Opt-in per repo: configure `checks` (start with `scope = "all"` if
   branch protection required-ness is uncertain; move to `"required"` once
   verified).
3. Rollback: drop the `checks` table — no persisted state needs undoing
   (check findings in existing ledgers read as ordinary findings; open ones
   must be resolved by review or closed by hand-deleting the ledger, the
   documented escape hatch).

## Open Questions

- The rollup's exact node spellings through `gh api graphql`
  (`detailsUrl`, StatusContext `targetUrl`) — settled by the first task
  against a live PR; changes no decision above.
