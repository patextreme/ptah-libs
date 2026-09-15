## Context

See proposal.md — Why. Multiple runners scan one label queue; GitHub has
no atomic test-and-set; ptah exposes no run id to scripts (storage-side
only). `docs/adr/0002-issue-claims-earliest-marker-wins.md` records the
claim decision. The stdlib's `gh` transport (`std/gh.run`, structured
outcome, JSON parsing) is the only library dependency; the playbook runs
in the consumer repository, so gh's own repo resolution (working
directory, `GH_REPO`) identifies the repository — no repo field in
config, mirroring how the pr playbook keeps repository context out of
config.

## Goals / Non-Goals

**Goals:**

- One operation, `pickUp`, whose whole job is: scan → claim → brief.
- Safe under concurrent runners with only marker comments and read-backs.
- Agent-free: no sessions, no judge, no ask — nothing to configure but
  vocabulary.

**Non-Goals:**

- Triage, release/reclaim, run-id identity, orchestration to a PR (all
  deferred; see proposal).
- No retry/judge machinery: a failed `gh` call raises loudly through the
  transport's outcome (`ok == false` → error carrying stderr) — the
  calling script's daemon decides what rescan means.

## Decisions

- **Agent-free playbook.** The facade contract (constructor + data
  config + typed operations) nowhere mandates sessions; `pickUp` needs
  none because the intelligence is the protocol, not a prompt. Config is
  `{ queueLabel: string (required), claimedLabel: string? }` — the
  smallest config of any playbook, and `ptah check` enforces the required
  field.
- **Claim body: marker + fixed legible sentence, no data fields.** The
  comment is the marker `<!-- ptah:issue-claim -->` followed by one fixed
  sentence (e.g. "Claimed by a ptah run for automated pickup."). A
  marker-only body renders as an empty comment on GitHub — the fixed
  sentence keeps the claim human-visible without carrying identity (the
  posting gh account is the identity; ADR 0002).
- **Claim flow (per attempt):** fetch the candidate's comments → if any
  claim marker exists, the issue is ineligible, next candidate → post
  the claim comment → (if `claimedLabel` configured) add it, keeping the
  queue label → read the claims back → earliest claim comment by gh
  `createdAt` (comment id tie-break) wins. Loser: scan mode moves to the
  next eligible issue; explicit-number mode raises a lost-claim error.
  Every attempt therefore reads comments at most twice (pre-check +
  read-back) — contention correctness never depends on the label.
- **`claimedLabel` is an optimization and a courtesy, not the source of
  truth.** When configured, the scan filters claimed issues from the
  single `gh issue list --json` response (labels arrive in the query);
  when absent, the pre-check comment read does the work. The label is
  also the human's stale-claim lever: removing it returns the issue to
  eligibility.
- **Deterministic ordering client-side.** `gh issue list` ordering is
  gh's business; the playbook sorts eligible issues by number ascending
  itself so "oldest first" is exact and stable.
- **Outcomes as data.** `pickUp()` returns
  `{ status = "claimed", brief = { number, url, title, body, claimCommentId } }`
  or `{ status = "no-eligible-issue", scanned = <count> }` — never a
  raise for an empty queue. Explicit-number misses and lost claims
  raise with the reason (eligibility condition, or contention loss).

## Risks / Trade-offs

- [Same-second claim comments make `createdAt` ambiguous] → comment id
  (monotonic) is the tie-break; the protocol stays deterministic.
- [A dead runner's claim blocks an issue forever] → accepted (explored
  and chosen): the claim is audit trail; a human removes `claimedLabel`
  to re-queue. Reclaim automation is deferred with ADR 0002.
- [Rate limits from comment reads on large queues] → one list query +
  per-candidate reads only as attempts proceed (oldest first), so a
  healthy queue costs two calls per pickup, not N.
- [Marker literal is wire format] → fixed at `<!-- ptah:issue-claim -->`
  now; changing it later is a read-old-write-new migration, per the
  ADR-0001 wire-freeze principle.

## Migration Plan

Additive: new export `issue`, new directory. Sequenced after
`rename-pr-review-loop-to-pr` lands so the export table is written once
in its final shape. No consumer breakage; prior tags unaffected.

## Open Questions

(none — the deferrable unknowns are enumerated as Non-Goals)
