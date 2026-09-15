## Why

Agentic runs need a queue they can safely draw work from: issues a human
has marked ready for development. With multiple runners scanning the same
label, pickup needs a claim protocol GitHub doesn't natively provide.
This adds the first entity-named playbook alongside the renamed `pr`,
giving the library the `issue` / `pr` / `openspec` triad (ADR 0001) —
deliberately minimal, so real usage can shape what a `triage` operation
needs later.

## What Changes

- New playbook `issue` at `playbooks/issue/`, exported as `issue` beside
  `openspec` and `pr`.
- One operation, `pickUp`:
  - scans the configured **queue label** (required config, no default —
    the vocabulary is the repo's), oldest by issue number first, or
    claims a specific issue by number;
  - eligibility: queue label present and not already claimed;
  - **claim**: a bare `<!-- ptah:issue-claim -->` marker comment on the
    issue plus an optional configured `claimedLabel` transition (added,
    never removing the queue label), with **earliest-wins read-back
    verification** — after posting, the claims are read back and the
    earliest claim comment (by the platform creation timestamp; on a tie,
    the lowest numeric comment id wins, since ids increase monotonically)
    wins; a losing runner backs off and takes the next eligible issue;
  - returns a typed outcome discriminated on `status`: `claimed`
    carrying a **brief** `{ number, url, title, body, claimCommentId }`
    — the consumer's script drives the work from it — or
    `no-eligible-issue` carrying the scan summary (the count of issues
    scanned), never raising on an empty queue;
- The playbook is agent-free: no work sessions, no judge, no
  session-config, no ask. The claim protocol is pure `gh` transport.
- No release protocol: a claim is audit trail, retired when the issue
  closes; the claim marker comment is the source of truth for
  claimedness, and a human clears a stale claim by deleting every claim
  marker comment on the issue (a losing runner leaves its losing marker
  in place, so all markers must go; removing the optional `claimedLabel`
  is cosmetic and does not requeue).
- Triage is explicitly out of scope (deferred until real usage shapes
  it), as are reclaim, run ids, and orchestration to a reviewed PR.

Decisions recorded in `docs/adr/0002-issue-claims-earliest-marker-wins.md`.

## Capabilities

### New Capabilities

(none — the issue playbook joins the existing `playbooks` capability,
like the openspec and PR playbooks before it)

### Modified Capabilities

- `playbooks`: the package-consumption export surface gains `issue`, and
  a new requirement covers the issue pickup playbook's behavior (queue
  scan, claim protocol, brief, eligibility, and the declared boundary —
  no agent, no judge, no release).

## Impact

- `playbooks/issue/` — new `playbook.luau` (+ README with declared
  environment requirements: `gh` CLI on PATH with credentials).
- `lib.luau` — export `issue` (assumes the rename change has landed; if
  sequenced before it, the export table temporarily carries both names'
  final state).
- `README.md`, `playbooks/README.md` — playbook index entries.
- `docs/adr/0002-issue-claims-earliest-marker-wins.md` — requeue sentence
  aligned with the marker-as-source-of-truth decision (delete every claim
  marker; label removal is cosmetic).
- Consumers — additive: no existing export or behavior changes.
