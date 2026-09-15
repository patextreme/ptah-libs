# issue playbook

Agent-free issue pickup. Scan a repo-configured **queue label** and claim
the oldest eligible issue for the calling script to work on, returning a
typed **pickup brief**. The intelligence is the claim protocol — a marked
comment plus an earliest-wins read-back — not a prompt, so the playbook
creates no sessions, ships no judge, and asks nothing.

`pickUp` is the whole playbook: scan → claim → brief. Everything else
(triage, reclaim, a release protocol, run-id identity, orchestration to a
reviewed PR) is deliberately deferred. The claim decision is recorded in
[`docs/adr/0002-issue-claims-earliest-marker-wins.md`](../../docs/adr/0002-issue-claims-earliest-marker-wins.md).

## The queue and eligibility

The **queue label** is a required config value with no default: the label
vocabulary is the repository's, never the playbook's. It is a human's
assertion that an issue is ready for development.

The scan reads **every** open issue carrying the queue label through the
REST issues endpoint (`gh api --paginate --slurp
repos/{owner}/{repo}/issues` with `state=open`, `sort=created`,
`direction=asc`, `labels=<queueLabel>`), flattens the pages, drops pull
requests (they share the issues endpoint), and orders candidates by issue
number ascending. That whole-queue read is why the scan does not use `gh
issue list`: its returned window is capped and newest-first, so it cannot
carry "oldest first" for a queue larger than one page.

Eligibility considers exactly two signals:

1. the queue label is present, and
2. the issue carries **no claim marker comment**.

Nothing else — no triage verdict, no label state. The optional
`claimedLabel` is queue hygiene for humans only: it is added on claim but
is never read as a gate and never narrows the candidate set.

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

Each attempt (`pickUp`, per candidate) runs:

1. **Pre-check** — read the candidate's comments; if any claim marker
   exists, the issue is ineligible and the run moves to the next
   candidate.
2. **Post** — post the claim comment.
3. **Label** — when `claimedLabel` is configured, add it. The queue label
   is never removed (it is the human's readiness assertion).
4. **Read-back** — read all claim markers back. The **winner** is the
   earliest claim comment by the platform creation timestamp
   (`created_at`), with the numeric REST comment `id` as tie-break — the
   lowest id wins, since ids increase monotonically with creation. (The
   GraphQL node id is an opaque string and is not orderable, which is why
   the read-back goes through the REST comments endpoint.)
5. **Decide** — if the runner's own comment is the earliest, it won and
   `pickUp` returns the brief. Otherwise it lost: it writes **nothing
   further** and backs off — to the next eligible issue in scan mode, or a
   lost-claim error when a specific number was requested.

Every attempt reads comments at most twice (pre-check and read-back).
Contention correctness never depends on the label.

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

## Operations

- `ops:pickUp()` — scan and claim the oldest eligible issue. Returns a
  typed outcome:
  - `{ status = "claimed", brief = { number, url, title, body, claimCommentId } }`
    — enough for the calling script to drive the work without re-fetching
    the issue. `claimCommentId` is the winning claim's numeric REST
    comment id. The brief carries no agent-authored content and no triage
    verdict.
  - `{ status = "no-eligible-issue", scanned = <count> }` — the scan
    found nothing eligible (empty queue or every queued issue claimed).
    Scanning an empty queue never raises.
- `ops:pickUp(number)` — claim that issue by number, only if eligible. A
  miss raises with the reason: the issue lacks the queue label, or it is
  already claimed (including a lost contention). Explicit mode never
  returns `no-eligible-issue`.

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
marker comment alone.

## Environment requirements (declared, not bundled)

- **`gh` CLI on PATH with credentials** — the queue scan, the claim
  comment, the optional label, and the read-back are all `gh` calls
  through `std/gh.run`. A failed call raises loudly through the transport's
  outcome (its stderr in the error); the calling script decides what a
  rescan means.
- **Runs in the target repository** — repository identification is by the
  invocation directory. `ptah.exec` inherits the ptah process's working
  directory (the directory the consumer invokes the workflow from, i.e.
  the consumer repo), and `gh` with no `--repo` targets that repo;
  `GH_REPO` overrides as usual. There is no repo field in config.
- **Concurrent runners are safe** — the earliest-claim read-back makes
  pickup safe under concurrent runners; a loser backs off.
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
