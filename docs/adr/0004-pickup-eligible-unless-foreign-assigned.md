# Pickup is eligible unless foreign-assigned

ADR 0003's own-assignments scope over-restricted the queue label: because
eligibility required the authenticated account among the assignees, a
labeled, unclaimed issue with no assignee was invisible to every runner —
`pickUp` returned `no-eligible-issue` with `scanned: 0`, indistinguishable
from a genuinely empty queue — and the label alone stopped being a
readiness assertion, since a human had to also assign the ticket to the
exact account that would run the factory. This ADR amends ADR 0003: the
assignment signal flips from "mine" to "not foreign". Eligibility is the
labeled queue minus foreign-assigned issues — an issue with no assignees
is eligible, an issue whose assignees include the authenticated account
is eligible, and only an issue assigned exclusively to other accounts is
ineligible. ADR 0003's among-not-sole rule stands: a teammate cc'd
alongside the account is not a foreign assignee. The scan drops the
server-side `assignee=<login>` narrowing — the issues endpoint takes a
single `assignee` term and cannot express "none or mine" as a union — so
the client-side foreign-assignment check is the only assignment signal,
and the `no-eligible-issue` scan summary counts labeled issues that are
not foreign-assigned. Explicit-number pickup raises "assigned to another
account" as its own reason. Identity resolution (`GET /user`) stays: it
feeds the foreign-assignment check and the post-win self-assign, and the
assignee-write environment floor (triage or higher) is unchanged.

Consequences recorded rather than discovered later: an unassigned issue
in a shared queue is visible to every runner account, so cross-account
contention widens from "multi-assignee with the account cc'd" to
"unassigned" — the earliest-claim read-back already decides it, and a
loser still writes nothing but its own marker. A requeued issue stays
assigned to the account that claimed it (the winner's self-assign is not
part of the release), so it still returns to that account's queue. An
issue assigned to the authenticated account *and* to another account
stays eligible, as ADR 0003 intended — the among-not-sole rule and a
strict "not assigned to others" wording genuinely diverge on that case,
and among-not-sole wins.

Rejected: keeping ADR 0003's gate (the label stops asserting readiness,
and an unassigned queue reads as empty), merging two server-side passes
(an unassigned scan plus an own-assignee scan — two paginated reads and
a merge for what one client-side check over one read decides), exclusive
"sole-assignee must be me" eligibility (reintroduces the cc'd-teammate
failure ADR 0003 already rejected), and a configured account identity
(decouples check identity from claim identity for no evident use).
