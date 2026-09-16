## Why

Pickup currently claims the oldest labeled, unclaimed issue in the queue
regardless of who it is for. Repos route work by assigning issues to the
account that should do it, and a runner drawing an issue assigned to
someone else takes work that was never its. Pickup must respect that
routing: a run picks up only what is assigned to its own account.

## What Changes

- **BREAKING** — eligibility gains a third signal: the issue is
  eligible only if the run's own authenticated `gh` account is among its
  assignees. Queued issues assigned to another account, or to no one,
  are invisible to pickup. Consumers whose queues carry unassigned
  issues must pre-assign or pin the prior tag (clean break, like the
  `prReviewLoop` rename).
- The account is hardcoded to the authenticated identity — no config
  field — so the eligibility filter and the claim share one identity.
  "Among the assignees", not sole assignee: a teammate cc'd as assignee
  leaves the issue eligible (contention stays the marker protocol's
  job). Decision recorded in
  [`docs/adr/0003-pickup-scoped-to-own-assignments.md`](../../../docs/adr/0003-pickup-scoped-to-own-assignments.md).
- **Winners-only writes**: nothing but the claim marker is written
  before the read-back confirms the win. The winning runner adds itself
  as assignee after winning, and `claimedLabel` moves to that same
  post-win slot (today a loser adds `claimedLabel` before learning it
  lost). A cosmetic write failing after a won claim raises.
- The scan narrows server-side (`assignee=<login>`) with the client-side
  assignee check as the authoritative signal, mirroring how the queue
  label is filtered and verified today.
- `no-eligible-issue`'s `scanned` count now means issues examined under
  the full scope (labeled **and** assigned to me), not the whole labeled
  queue.
- Explicit `pickUp(number)` enforces the same gate and raises "not
  assigned to you" as its own reason.
- New declared environment requirement: the `gh` token needs assignee
  write (triage or higher) on the target repository.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `playbooks`: the issue pickup playbook's eligibility (two signals →
  three, with the authenticated account among the assignees), the claim
  protocol's write ordering (winners-only cosmetic writes, self-assign
  on win), the `no-eligible-issue` scan summary's meaning, and the
  explicit-mode error reasons.

## Impact

- `playbooks/issue/playbook.luau` — eligibility, scan, attempt/write
  ordering, errors; `playbooks/issue/README.md` — eligibility, claim
  protocol, environment requirements.
- `openspec/specs/playbooks/spec.md` — "Issue pickup playbook" and
  "Issue claim protocol" requirements.
- Consumers of the `issue` playbook: behavior break for unassigned
  queues; `Config` type unchanged; outcome shape unchanged (`scanned`
  meaning shifts); brief unchanged.
- New environment requirement on the runner token: assignee write
  (triage+) in the target repo; `GET /user` joins the scan's `gh` calls.
- Docs already landed: `CONTEXT.md` (Assignment, Eligibility), ADR 0003.
