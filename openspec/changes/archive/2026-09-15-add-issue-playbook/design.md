## Context

See proposal.md — Why. Multiple runners scan one label queue; GitHub has
no atomic test-and-set; ptah exposes no run id to scripts (storage-side
only). `docs/adr/0002-issue-claims-earliest-marker-wins.md` records the
claim decision. The stdlib's `gh` transport (`std/gh.run`, structured
outcome, JSON parsing) is the only library dependency; the playbook runs
in the consumer repository, so gh's own repo resolution identifies the
repository — `ptah.exec` inherits the ptah process cwd (the directory the
consumer invokes the workflow from, i.e. the consumer repo), and `gh`
with no `--repo` targets that repo (`GH_REPO` overrides as usual). There
is no repo field in config, mirroring how the pr playbook keeps
repository context out of config.

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
- **Comment reads go through the REST endpoint.** Comments are read
  from `repos/{owner}/{repo}/issues/<n>/comments` (flattened
  `--paginate --slurp` output, the idiom `pr/playbook.luau` already
  uses). Only the numeric REST `id` is orderable — it increases
  monotonically; the GraphQL node id that `gh --json comments` exposes
  is an opaque base64 string and is not usable as an order key.
- **Claim flow (per attempt):** fetch the candidate's comments → if any
  claim marker exists, the issue is ineligible, next candidate → post
  the claim comment → (if `claimedLabel` configured) add it, keeping the
  queue label → read the claims back → earliest claim comment by the
  platform creation timestamp (`created_at`) with the numeric REST
  comment `id` as tie-break — the lowest id wins, since ids increase
  monotonically with creation — is the winner. Loser: scan mode moves to the
  next eligible issue; explicit-number mode raises a lost-claim error.
  The loser leaves its own losing marker in place (it writes nothing
  further), so a requeue deletes every claim marker on the issue, never
  just the winner's. Every attempt therefore reads comments at most twice (pre-check +
  read-back) — contention correctness never depends on the label.
- **`claimedLabel` is cosmetic queue state, never a gate.** The queue
  label is enforced by the scan's list query (`labels=<queueLabel>`); no
  candidate is ever admitted or excluded by reading `claimedLabel`. The
  only per-candidate gate is the claim-marker pre-check: a leftover
  `claimedLabel` on a marker-less issue never keeps it out of the scan,
  and `claimedLabel` never narrows the candidate set. Removing
  `claimedLabel` is cosmetic hygiene and never requeues an issue.
- **Sorted, whole-queue scan.** `gh issue list` returns a capped,
  newest-first window (`--limit` default 30), so its result cannot carry
  "oldest first" for a queue larger than one page. The playbook instead
  reads every open issue carrying the queue label through `gh api
  --paginate --slurp` on `repos/{owner}/{repo}/issues` with `state=open`,
  `sort=created`, `direction=asc`, and the label filter — the same
  `--paginate --slurp` idiom the comment reads use. `{owner}`/`{repo}`
  resolve from the invocation directory (or `GH_REPO`), exactly like bare
  `gh`, so config still carries no repo field. Pull requests share the
  REST issues endpoint and are filtered out (an entry carrying a
  `pull_request` key is not an issue); the brief's `url` comes from
  `html_url`. `created` ascending is `number` ascending, so the global
  oldest eligible issue is always in the result; a defensive client-side
  sort by number keeps "oldest first" exact and stable.
- **Outcomes as data.** `pickUp()` returns
  `{ status = "claimed", brief = { number, url, title, body, claimCommentId } }`
  (the brief's `claimCommentId` is the numeric REST comment id)
  or `{ status = "no-eligible-issue", scanned = <count> }` — never a
  raise for an empty queue. Explicit-number misses and lost claims
  raise with the reason (eligibility condition, or contention loss).

## Risks / Trade-offs

- [Same-second claim comments make the creation timestamp ambiguous]
  → the numeric REST comment id (monotonically increasing) is the
  tie-break; the protocol stays deterministic. The GraphQL node id is
  not orderable, so the tie-break reads the REST `id` specifically.
- [A dead runner's claim blocks an issue forever] → accepted (explored
  and chosen): the claim is audit trail; a human deletes every claim
  marker comment to re-queue (removing `claimedLabel` alone does not — it
  is cosmetic, and losing markers are accepted noise, so every marker
  must go). Reclaim automation is deferred with ADR 0002.
- [Rate limits on large queues] → one paginated list read (`--paginate`
  follows `Link` headers; each page is one request) plus two logical
  comment reads per pickup (pre-check + read-back, oldest first) rather
  than a comment read per queued issue; `--paginate` adds requests only
  for queues and comment threads larger than one page.
- [Marker literal is wire format] → fixed at `<!-- ptah:issue-claim -->`
  now; changing it later is a read-old-write-new migration, per the
  ADR-0001 wire-freeze principle.

## Migration Plan

Additive: new export `issue`, new directory. Sequenced after
`rename-pr-review-loop-to-pr` lands so the export table is written once
in its final shape. No consumer breakage; prior tags unaffected.

## Open Questions

(none — the deferrable unknowns are enumerated as Non-Goals)
