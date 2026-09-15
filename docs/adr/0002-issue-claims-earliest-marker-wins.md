# Issue claims: earliest marker comment wins

Multiple runners scan one label queue, and GitHub offers no atomic
test-and-set. A claim is a dedicated issue comment marked
`<!-- ptah:issue-claim -->` — a bare marker, no body fields (a configured
runner identity was considered and omitted: the gh comment's own author
and timestamps carry identity). The winner is the earliest claim comment
by the platform creation timestamp, with the numeric comment id as
tie-break, verified by reading the claims back after posting — a loser backs off and takes the next
eligible issue. The optional label transition
is a human-legible filter, never the source of truth (label edits race).
There is no release protocol: a claim is audit trail, retired naturally
when the issue closes. Reclaim stays deferred even though concurrency is
real — a human clears a stale claim by deleting every
`<!-- ptah:issue-claim -->` marker comment on the issue, which returns the
issue to eligibility (removing the claimed label alone is cosmetic and
does not requeue). A losing runner never removes its own losing marker;
losing markers are accepted audit noise, so a requeue means deleting all
of them. ptah exposes no run id to scripts today
(`.ptah/runs/` ids are storage-side only), and a claim's identity is the
posting gh account, not the execution.

Rejected: gh assignees (no exclusivity — adding an assignee never fails),
label-swap-only (a race window between list and edit), and branch
reservation (atomic, but demands push rights at claim time).
