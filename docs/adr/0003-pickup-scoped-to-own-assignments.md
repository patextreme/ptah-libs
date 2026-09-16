# Pickup is scoped to the runner's own assignments

Pickup eligibility gains a third signal beside the queue label and the
claim marker: the issue is assigned to the run's own authenticated gh
account — among its assignees, not exclusively (a teammate cc'd as
assignee leaves the issue eligible). Assignment is a human's routing
assertion and carries no exclusivity, so ADR 0002's rejection of
assignees as the claim mechanism stands: there assignees were rejected as
the *claim*; here they only scope which issues a runner considers, and
the earliest-marker read-back still decides contested issues —
cross-account contention stays possible precisely because eligibility is
"among", and same-account contention never went away. The account is
hardcoded to the authenticated identity (resolved from `GET /user`; the
repo issues endpoint rejects the literal `@me`), so the eligibility
filter and the claim share one identity, with no config field. The
winner records itself as assignee after the read-back confirms it won,
and the claimed label moves to that same post-win slot: nothing but the
marker is written before the read-back says won, so a losing runner
writes nothing beyond its marker. A cosmetic write failing after a won
claim raises loudly — assignment failure is usually a systemic permission
problem (the token now needs assignee write, i.e. triage, on the target
repo), and silence would leave queues dark. Explicit-number pickup
enforces the same gate and raises "not assigned to you" as its own
reason; the `no-eligible-issue` scan summary counts issues examined under
the full scope, not the whole labeled queue.

Amended by [ADR
0004](0004-pickup-eligible-unless-foreign-assigned.md): the gate flips
from "the account is among the assignees" to "not foreign-assigned" — an
unassigned issue becomes eligible, the scan drops the `assignee=`
narrowing, and `scanned` re-counts — while the among-not-sole rule, the
single authenticated identity, the winners-only writes, and the
assignee-write floor stand.

Rejected: sole-assignee eligibility (a cc'd teammate would silently kill
pickup; contention is the marker's job), a configured assignee identity
(decouples filter identity from claim identity for no evident use),
self-assign in the pre-readback slot (a loser would assign itself onto
the winner's issue), and soft-failing cosmetic writes (silent
environment drift).
