## Context

The issue pickup playbook (`playbooks/issue/playbook.luau`) scans a queue
label, claims the oldest eligible issue via the earliest-marker protocol
(ADR 0002), and returns a brief. Eligibility today is two signals: queue
label present, no claim marker. The proposal adds assignment scoping and
winner-only writes; the requirements are the delta spec, the decision
record is ADR 0003, and the terms are in `CONTEXT.md` (Assignment,
Eligibility).

## Goals / Non-Goals

**Goals:**

- A run picks up only issues assigned to its own authenticated `gh`
  account, with one identity shared by filter and claim.
- Nothing but the claim marker is written before the read-back says won;
  the winner self-assigns and adds `claimedLabel` post-win.
- Diagnosable dark queues: `scanned` reports what the scope actually
  examined.

**Non-Goals:**

- No release protocol, reclaim automation, or run ids (ADR 0002 keeps
  these deferred).
- No config field for the account; no sole-assignee mode; no changes to
  the `pr` playbook, the brief's shape, or `Config`'s type.

## Decisions

- **Identity: the authenticated account, hardcoded.** Resolved once per
  `pickUp` (memoizable on the instance) via `gh api /user` → `login`.
  Rejected a configured `assignee` field: it decouples filter identity
  from claim identity for no evident use, and the repo's "vocabulary is
  config" stance covers genuinely repo-specific words (the queue label),
  not the runner's own account. Note the REST issues endpoint rejects
  the literal `@me` (verified: 422 Validation Failed), so the login must
  be resolved; the scan cannot pass `@me` through.
- **Filter location: server param + authoritative client check.** The
  scan passes `assignee=<login>` to shrink the payload, and keeps a
  client-side check on the issue's `assignees` array beside the existing
  `hasQueueLabel` check. The client check is authoritative so eligibility
  is exact regardless of param semantics, and it is where "among the
  assignees" is implemented. Rejected client-side-only: same code
  correctness, strictly larger payload for no extra truth.
- **Write ordering: winners-only.** Today the sequence is pre-check →
  post marker → add `claimedLabel` → read-back → decide, so a loser adds
  the label before learning it lost. New sequence: pre-check → post
  marker → read-back → **if won**: self-assign, then `claimedLabel`,
  return brief; **if lost**: return/raise having written nothing but the
  marker. Self-assign uses the existing "add assignees" endpoint with the
  resolved login; it adds, never removes or replaces. This makes
  "a loser writes nothing" literally true and makes self-assign
  race-free by construction. Rejected slotting self-assign in the old
  pre-readback position: under cross-account contention (possible,
  because eligibility is "among") a loser would assign itself onto the
  winner's issue — polluting a signal that gates eligibility.
- **Failure semantics: cosmetic post-win writes raise.** Consistent with
  `claimedLabel` today; assignment failure is most likely systemic (the
  token lacks assignee write — the new declared environment requirement:
  triage access or higher in the target repo). Known edge: a raise after
  a won claim leaves our marker on the issue, so rescans skip it until a
  human deletes the markers — identical to today's label behavior, and
  the playbook's stated philosophy is that the calling script decides
  what a rescan means. Rejected soft best-effort: silent environment
  drift leaves queues dark with no signal.
- **`scanned` meaning: scope-examined count.** With the server-side
  assignee param, the scan response only contains labeled issues
  assigned to the account, so `scanned` naturally counts those. Rejected
  a second unfiltered request to also report the whole queue size: it
  doubles payload against the narrowing's point; a `scanned: 0` dark
  queue is diagnosed with one `gh issue list -l <label>`.

## Risks / Trade-offs

- [Consumers with unassigned queues go silently dark] → **BREAKING** is
  declared in the proposal; clean break, defer by pinning the prior tag;
  README ops note that `scanned: 0` means nothing in the queue is
  assigned to the runner's account.
- [The permission floor rises: comments worked read-only, assignee
  writes need triage+] → declared environment requirement in README and
  spec; hard failure keeps it loud.
- [`GET /user` adds a call per `pickUp`] → memoize on the instance; one
  cheap call against a whole-queue scan.
- [Assignment mutates mid-run (human un-assigns while we work)] →
  eligibility is evaluated pre-claim only, exactly like queue-label
  removal today; the read-back never consults assignees.

## Migration Plan

Single-repo library, no persisted state changes (the wire marker is
untouched). Land the playbook change, README, and spec sync together;
consumers pin the prior tag to defer. No rollback beyond `git revert` —
nothing protocol-level changes, and issues claimed by the old code carry
markers the new code reads identically.

## Open Questions

None — the exploration (ADR 0003) settled identity, semantics, filter
location, write ordering, failure semantics, and outcome meaning. One
implementation-time verification, not a design unknown: the exact GitHub
permission floor for self-assign (triage vs. any authenticated user on
public repos) — the task declares the requirement and asserts the
documented floor.
