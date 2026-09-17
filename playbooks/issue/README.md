# issue playbook

Agent-free issue pickup. Scan a repo-configured **queue label** and claim
the oldest eligible issue in it, returning a typed **pickup brief**. The
intelligence is the claim protocol — a marked comment plus an
earliest-wins read-back — not a prompt, so the playbook creates no
sessions, ships no judge, and asks nothing.

`pickUp` is the whole playbook: scan → claim → brief. Everything else
(triage, reclaim, a release protocol, run-id identity, orchestration to a
reviewed PR) is deliberately deferred. The decisions are recorded in
[`docs/adr/0002-issue-claims-earliest-marker-wins.md`](../../docs/adr/0002-issue-claims-earliest-marker-wins.md)
(the claim protocol),
[`docs/adr/0003-pickup-scoped-to-own-assignments.md`](../../docs/adr/0003-pickup-scoped-to-own-assignments.md)
(the assignment scope, as first drawn), and
[`docs/adr/0004-pickup-eligible-unless-foreign-assigned.md`](../../docs/adr/0004-pickup-eligible-unless-foreign-assigned.md)
(its amendment: only foreign-assigned issues are ineligible).

> **BREAKING — unassigned queue issues are now eligible.** Previously
> (ADR 0003) a run picked up only issues whose assignees included its own
> authenticated `gh` account, so labeling a ticket was not enough — a
> human also had to assign it to the exact account that would run the
> factory, and an unassigned queue read as empty (`scanned: 0`, like a
> genuinely empty queue). Eligibility is now **the labeled queue minus
> foreign-assigned issues**: no assignees → eligible (visible to *every*
> runner account), the account among the assignees → eligible (a teammate
> cc'd alongside is not a foreign assignee), assigned only to other
> accounts → invisible. Cross-account contention on unassigned issues is
> decided by the earliest-claim read-back, and a loser writes nothing but
> its own marker. Pin the prior tag to defer the upgrade. No config field
> was added.

## The queue and eligibility

The **queue label** is a required config value with no default: the label
vocabulary is the repository's, never the playbook's. It is a human's
assertion that an issue is ready for development.

The scan reads **every** open issue carrying the queue label through the
REST issues endpoint (`gh api --paginate --slurp
repos/{owner}/{repo}/issues` with `state=open`, `sort=created`,
`direction=asc`, `labels=<queueLabel>`), flattens the pages, drops pull
requests (they share the issues endpoint), and orders candidates by issue
number ascending. That whole-queue read is why the scan does not use
`gh issue list`: its returned window is capped and newest-first, so it
cannot carry "oldest first" for a queue larger than one page.

The scan first resolves the runner's identity from `gh api /user` →
`login`. One identity then serves both the foreign-assignment check and
the claim. There is **no** server-side assignee narrowing: the issues
endpoint takes a single `assignee` term and cannot express "unassigned
**or** mine" as a union, so the **client-side** check (reading each
issue's `assignees` array) is the only assignment signal.

Eligibility considers exactly three signals:

1. the queue label is present,
2. the issue is **not assigned to another account** — no assignees at
   all, or the run's own authenticated account *among* the issue's
   assignees (a teammate cc'd alongside it is not a foreign assignee);
   only an issue assigned exclusively to other accounts is ineligible
   (contention stays the marker protocol's job), and
3. the issue carries **no claim marker comment**.

Only the third signal needs a comments read. Nothing else — no triage
verdict, no label state — affects eligibility. The optional `claimedLabel`
is queue hygiene for humans only: it is added on a won claim but is never
read as a gate and never narrows the candidate set.

## The claim protocol

GitHub has no atomic test-and-set, so a claim is a **dedicated issue
comment** carrying the marker

```
<!-- ptah:issue-claim -->
```

followed by one fixed legible sentence (a bare marker would render as an
empty comment). The comment carries no protocol fields: the posting `gh`
account is the identity and the comment's platform timestamps carry order.
The claim marker comment is the **source of truth for claimedness**.

Each attempt (`pickUp`, per candidate) runs the checks in order — queue
label → foreign-assignment → claim marker — then:

1. **Pre-check** — read the candidate's comments; if any claim marker
   exists, the issue is ineligible and the run moves to the next
   candidate.
2. **Post** — post the claim comment.
3. **Read-back** — read all claim markers back. The **winner** is the
   earliest claim comment by the platform creation timestamp
   (`created_at`), with the numeric REST comment `id` as tie-break — the
   lowest id wins, since ids increase monotonically with creation. (The
   GraphQL node id is an opaque string and is not orderable, which is why
   the read-back goes through the REST comments endpoint.)
4. **Decide — winners only** — nothing but the claim marker is written
   before this point.
   - **Won** (the runner's own comment is the earliest): record the win on
     the issue — add the authenticated account as an assignee (the
     assignees endpoint **adds**; it never removes or replaces anyone),
     then, when `claimedLabel` is configured, add it — and return the
     brief. A post-win cosmetic write that fails **raises** with the
     transport's error; the claim marker remains the source of truth and
     the calling script decides what a rescan means.
   - **Lost**: write **nothing further** (its own losing marker stays as
     accepted audit noise) and back off — to the next eligible issue in
     scan mode, or a lost-claim error when a specific number was
     requested.

Every attempt reads comments at most twice (pre-check and read-back).
Contention correctness never depends on the label or on assignees.

## Re-queueing a stale claim

There is no release protocol. A claim is audit trail, retired naturally
when the issue closes. A human re-queues an issue by **deleting every
claim marker comment** on it, which returns it to eligibility.

- Removing `claimedLabel` alone is **cosmetic** and does not re-queue — the
  marker is the source of truth, not the label.
- A losing runner leaves its own losing marker in place (it writes nothing
  further), so **all** claim markers must be deleted. An issue carrying
  only a losing marker — its winner's marker already deleted — remains
  ineligible until the last marker goes.
- The assignment a winner recorded is **not** part of the release: a
  re-queued issue stays assigned to the account that claimed it, so it
  returns to that account's queue.

## Operations

- `ops:pickUp()` — scan and claim the oldest eligible issue. Returns a
  typed outcome:
  - `{ status = "claimed", brief = { number, url, title, body, claimCommentId } }`
    — enough for the calling script to drive the work without re-fetching
    the issue. `claimCommentId` is the winning claim's numeric REST
    comment id. The brief carries no agent-authored content and no triage
    verdict.
  - `{ status = "no-eligible-issue", scanned = <count> }` — the scan
    found nothing eligible. `scanned` counts the issues **examined under
    the full scope** — carrying the queue label *and* not assigned to
    another account — not the whole labeled queue. An ops note:
    **`scanned: 0` means every labeled issue in the queue is assigned to
    other accounts (or the queue is empty)** (diagnose with
    `gh issue list -l <queueLabel>`). Scanning an empty or entirely
    foreign queue never raises.
- `ops:pickUp(number)` — claim that issue by number, only if eligible. A
  miss raises with the reason: the issue **lacks the queue label**, is
  **assigned to another account**, or is **already claimed** (including a
  lost contention). Explicit mode never returns `no-eligible-issue`, and
  a miss posts nothing.

## Config (data only)

```lua
local issue = require("./luau_packages/ptah_libs").issue

local ops = issue.new({
	queueLabel = "ready-for-dev",  -- required, no default
	claimedLabel = "in-progress",  -- optional, cosmetic queue state
})

local outcome = ops:pickUp()
if outcome.status == "claimed" then
	-- outcome.brief.number, .url, .title, .body, .claimCommentId
else
	-- outcome.scanned
end
```

`queueLabel` is required and `ptah check` reports a missing field by name.
`claimedLabel` is optional; omit it and claimedness is carried by the
marker comment alone. There is no config field for the account: it is
always the authenticated identity.

## Environment requirements (declared, not bundled)

- **`gh` CLI on PATH with credentials** — the identity resolution
  (`GET /user`), the queue scan, the claim comment, the self-assign, the
  optional label, and the read-back are all `gh` calls through
  `std/gh.run`. A failed call raises loudly through the transport's
  outcome (its stderr in the error); the calling script decides what a
  rescan means.
- **Assignee write on the target repository — triage access or higher** —
  the winning run self-assigns after the read-back, and the GitHub issues
  API requires triage (or higher) to edit assignees. Without it, the
  post-win assignee write raises loudly (the marker stays). Reading
  comments alone needed no such access; this floor is new.
- **Runs in the target repository** — repository identification is by the
  invocation directory. `ptah.exec` inherits the ptah process's working
  directory (the directory the consumer invokes the workflow from, i.e.
  the consumer repo), and `gh` with no `--repo` targets that repo;
  `GH_REPO` overrides as usual. There is no repo field in config.
- **Concurrent runners are safe** — the earliest-claim read-back makes
  pickup safe under concurrent runners; a loser backs off. Cross-account
  contention is the common case on unassigned queue issues (eligibility
  no longer scopes the queue to one account) and the same marker protocol
  decides it.
- **One claim per issue is the expectation** — the protocol guarantees at
  most one *winner* per issue, but a contended issue carries the loser's
  losing marker as accepted audit noise until a human re-queues by
  deleting all markers.
- **No agent, judge, or ask** — the playbook creates no sessions and needs
  no agent registry entry; there is nothing to configure but vocabulary.

## Not in this playbook

- **Triage** — no verdict or classification affects eligibility.
- **Reclaim automation** — a dead runner's claim is cleared by a human
  deleting the markers (ADR 0002 keeps reclaim deferred).
- **Release protocol** — a claim is retired naturally when the issue
  closes.
- **Run ids** — ptah exposes no run id to scripts today (`.ptah/runs/` ids
  are storage-side only); identity is the posting `gh` account.
- **Orchestration** — driving a claimed issue to a reviewed PR is the
  calling script's job, composed around `pickUp`.
