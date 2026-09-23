# Implementation notes — gate-review-loop-convergence-on-checks

## Task 1.1 — the atomic check read, pinned live (2026-09-23)

The design's D3 query ran live through `gh api graphql` against real PRs.
Two corrections to the design's query *text* (no decision changes):

1. **`isRequired` argument is `pullRequestNumber`, not `pullNumber`.** The
   design's D3 snippet spells it `isRequired(pullNumber:$number)`; GitHub
   rejects that argument (`argumentNotAccepted`). The live-verified spelling
   is `isRequired(pullRequestNumber:$number)` — matching the proposal's
   prose (`CheckRun.isRequired(pullRequestNumber:)`). Required-ness IS
   readable; no scope-drift surface.
2. **Pagination metadata lives on the `contexts` connection**, not on
   `statusCheckRollup` itself: `statusCheckRollup { contexts(first: 100) {
   totalCount pageInfo { hasNextPage endCursor } nodes { … } } }`.

### The verified query

```graphql
query($owner:String!,$repo:String!,$number:Int!){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      headRefOid
      statusCheckRollup{
        contexts(first:100){
          totalCount
          pageInfo { hasNextPage endCursor }
          nodes{
            __typename
            ... on CheckRun { name status conclusion detailsUrl
                              isRequired(pullRequestNumber:$number) }
            ... on StatusContext { context state targetUrl }
          }
        }
      }
    }
  }
}
```

### Verified outputs

- `vercel/next.js` PR 99088 — 21 CheckRuns, `hasNextPage: false`, mixed
  states (`COMPLETED`/`SUCCESS`, `IN_PROGRESS`/`conclusion: null`), all
  `isRequired: false`.
- `microsoft/vscode` PR 337443 — `isRequired` reads **true** for branch-
  protected checks (`VS Code Check`, `Dependencies Check`, `license/cla`),
  proving required-ness flows through the same single query. Also surfaced
  conclusion `ACTION_REQUIRED` (not in D4's table — see the judgment call
  below).
- `rust-lang/rust` PR 163203 — 13 CheckRuns, none required (required-ness
  is per-repo branch protection, not per-API).
- `patextreme/ptah-libs` PR 35 (merged head) — `statusCheckRollup: null`
  when a repo runs no checks; and after posting a commit status to the
  head SHA, the rollup carries the StatusContext node live:

```json
{ "__typename": "StatusContext",
  "context": "ptah-libs-spike/status-probe",
  "state": "ERROR",
  "targetUrl": "https://example.com/status-probe" }
```

### Pinned facts

- **`headRefOid` and `statusCheckRollup` are siblings on `pullRequest`** —
  one query reads head + states atomically, as the design assumes.
- **`detailsUrl` needs no mapping** — for Actions runs it is already a
  deep link to the failing job
  (`https://github.com/<o>/<r>/actions/runs/<id>/job/<jobId>`); for
  external checks it is the provider's URL (`https://vercel.com/github`).
  It is carried verbatim as the finding's run-URL pointer.
- **`conclusion` is nil while a run is `IN_PROGRESS`/`QUEUED`** — the
  classifier must read `status` first (non-terminal status → pending) and
  only then `conclusion`.
- **StatusContext carries no `isRequired`** — with `scope = "required"`,
  commit statuses can never be required (branch protection's
  required-status-checks name check runs), so `"required"` scope filters
  them out; `"all"` scope includes them. (Design-consistent: required-ness
  is a CheckRun-only field.)
- **`statusCheckRollup` is `null`** for repos with no checks at all — the
  empty in-scope set, vacuously green per D4.
- **A required check absent from the rollup is unobservable via the
  rollup alone** (the subtlety D3's first task was to settle): a check
  that has never started simply does not appear as a node. Per the
  design's stated acceptance, this degrades to vacuous green under
  `"required"` scope — no branch-protection API join.

### Judgment calls recorded during the spike

- **Unlisted observed states classify as pending.** The live API surfaced
  conclusion `ACTION_REQUIRED` (a workflow awaiting maintainer approval),
  which D4's table does not name. Rule: any state not in D4's green or
  red sets classifies as pending — the only honest default, since the
  check has produced no verdict about the head. (Red would file a
  misleading finding; green would be a lie.)
- A test commit status was posted to the merged head of ptah-libs PR 35
  to pin the StatusContext shape; it is the spike's red-status fixture
  and was reset to `SUCCESS` after the scratch runs.

## Tasks 1.2–5.3 — implementation verification

The transport layer was verified **live** (real `gh` against real PRs):
classified snapshots for a red StatusContext (`scope = "all"` vs
`"required"`), a null rollup (vacuous green), pending checks with names,
and the truncation log (page cap lowered to 3 in a scratch copy so
`hasNextPage` trips for real). Config validation verified: every
misconfiguration errors at `M.new` naming the field.

The loop layer was verified **hermetically** (a mock `std/gh` + fake agents
driving the real playbook — loop runs post comments, so live-agent runs
against real PRs would pollute real PRs): 46 harness checks cover the
mid-loop exit (red files → fix turn → green converges), pending-at-budget
(bounded polls, named outcome, no fix turn after pending), all three resume
fast paths, the cap interplay at `maxIterations = 1`, `Outcome.checks`
(off / nil-from-review / gate inert for `review`), byte-identical ungated
status lines, the terminal-read degradation to `unknown`, the fix-turn
regression loop, STALE-as-pending, and dry-run honesty. Ledger flows
(tolerant reads, judge-blindness, one-finding-per-check identity, renders)
were verified with focused scratch scripts through the real parse/apply/
reconcile functions.

## Judgment calls recorded during implementation

1. **Unlisted rollup states are pending.** The live API surfaces
   `ACTION_REQUIRED` (a run awaiting maintainer approval), which D4's table
   does not name. Rule: any state outside D4's green/red sets classifies as
   pending — the only honest default for "no verdict about the head".
2. **A pass's convergence candidacy is judge-cleanliness over *review*
   findings** (`openBlockingReviewCount`), not all open blocking findings.
   An open check finding must not make a pass look judge-dirty: the judge
   can never reconcile it (it never saw it), so a ledger-wide open count
   would loop forever without consulting. The check findings' side of
   convergence is the gate consult's decision alone. Found by the harness
   (the loop churned to the cap ignoring green consults); the design's
   "wherever the loop can end converged … the loop consults" implies it.
3. **The terminal snapshot reuses a consult's read when it still describes
   the head** (no push since, tracked via `notePush`); only a stale or
   missing read triggers the fresh bounded-retry read. Saves one roundtrip;
   the snapshot is identical by the atomicity argument.
4. **Consult failures at any non-terminal point fail the operation** through
   the transport's error path (resumable; the ledger persists at each
   phase); only the terminal reporting read retries and degrades. The
   resume fast paths' consults count as decision points (their reads file
   findings).
5. **Close-all runs on a green rollup only** (spec-literal). A per-check
   green under an overall red rollup leaves its finding open until the
   rollup turns green — self-healing at the next consult, bounded by the
   cap.
6. **`scope = "required"` skips StatusContext nodes** — `isRequired` exists
   only on CheckRun, so a commit status's required-ness is unreadable
   through the rollup.
7. The spike's red StatusContext probe (posted to ptah-libs PR 35's merged
   head) was reset to `SUCCESS` after the live runs.

## Task 7.1 — delta scenario walk

Each scenario maps to verified behavior (harness check / scratch / live run):

- **gate off unchanged** — 5.1a/5.2a: zero GraphQL calls, byte-identical
  status line, `checks = off`; `review` nil and gate-inert when `checks` is
  configured.
- **red cannot end converged** — 4.1 (red → findings → fix turn; converges
  only on green), 4.3 (red at cap → non-converged, finding open).
- **fix-turn regression picked up** — regression scenario: the push breaks
  the check; the next pass's decision files the finding and fixes it.
- **resume consults** — 4.2a (clean+green: converge, no session, passes 0),
  4.2b (clean+red: files + fix turn directly), 4.2c (blockers: snapshot
  consult batches check + review findings in one fix prompt).
- **pending named** — 4.1b: bounded polls, named pending outcome in the
  status line and snapshot, no fix turn after pending.
- **STALE pending** — STALE StatusContext → pending, named, never red.
- **vacuous green** — extra scenario (unrequired red invisible under
  `"required"`); live null-rollup run in task 1.2.
- **never re-filed** — reconcile scratch: red-while-open updates in place
  (same id, fresh URL); green closes all; re-failure after green files a
  new id; pending files nothing.
- **judge-blind** — judgeblind scratch: the judge's ledger summary omits the
  check finding; a reconciliation record naming it is fully inert; harness
  confirms the judge prompt never contains it.
- **report/outcome carry state** — 4.1 (`; checks green`), 4.3
  (`; checks red: cargo`), 4.1b (`; checks pending: …`), 5.3 (terminal
  failures → `; checks unknown`, `Outcome.checks.state = "unknown"`, report
  still posted).
- **pointer not diagnosis** — finding title carries check name + run URL;
  the fix prompt hands over the pointer; the playbook executes no repo
  gate commands (transport is read-only over the rollup).
- **shared budget** — 4.3 (`maxIterations = 1`: no fix without a following
  pass); maxiter2 (default cap 10 executed exactly).
- **dry-run honesty** — dry-run scenario: no push prompt ever issued, the
  red check can never close, ends non-converged at the cap with the finding
  open, report names the red check.

`ptah check` is clean on every library module; `openspec validate
gate-review-loop-convergence-on-checks --strict` passes.
