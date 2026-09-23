# Proposal

## Why

The review-fix loop's convergence criterion is "no open blocking findings" over
judge-reconciled review findings — GitHub check state is invisible to it at
every decision point, so the loop can post "PR review report — converged" on a
pull request whose checks are failing. Worse, a regression introduced by the
loop's own fix turn is invisible to it *forever*: the loop's review passes run
whatever gates the reviewer happens to choose, and external CI is the only
thing that runs the repo's full gate. Observed on lace-id-portal PR #85 (run
`20260922143110-4293`): the loop posted its converged report at ~16:04–16:07Z
while the `cargo` and `devshell` checks had been failing since ~15:54–15:58Z
(merge state `UNSTABLE`); the lint regression they caught came from the loop's
own fix turn, was missed by the loop's own next review pass, and green CI was
achieved by a fix filed outside the loop.

Structurally: "converged" is defined purely over the ledger's findings, so the
readiness claim is unfalsifiable by the one signal that means "ready" on
GitHub; there is no feedback path from check failure back into the loop; and
every place the loop can end converged is affected — including the resume fast
path, which converges with no review pass at all. This change reverses one
half of a documented boundary: the spec and README currently forbid the
playbook from reading CI results at all (ADR 0008 records the un-decision —
platform check state comes in, executing repo gate commands stays out).

## What Changes

- **Check gate, config-gated, off by default**: a `checks` config table
  (`scope: "required" | "all"`, `pollBudgetMs` default 30 minutes,
  `pollIntervalMs` default 30 seconds) enables the gate; nil keeps behavior
  unchanged. `reviewFixLoop` only — inert for `review`, which has no
  convergence decision to gate (per the #34 facade split).
- **Checks join the convergence decision**: wherever the loop can end
  converged — the mid-loop exit and the resume clean-at-head fast path — the
  loop consults check state at the PR head first. Converged comes to mean
  ledger-clean AND checks-green at one head SHA.
- **Red checks become ledger findings, not a wait**: a failing check files a
  playbook-owned **check finding** (blocking, `source: "check"`, carrying the
  check name and failing run URL), the existing fix-turn machinery resolves
  it like any other blocking finding, and a green check at head closes it.
  One open finding per failing check name — updated across passes, never
  re-filed; a re-failure after a green close files a new finding.
- **Judge-blind ownership**: check findings are created, updated, and closed
  deterministically by the playbook from observed check state; the judge never
  sees them in its ledger summary and its reconciliation records are inert on
  them — the judge's prose never saw check state, so it can never classify
  them.
- **Bounded poll, named outcome**: pending checks poll within the budget at
  convergence decisions only; checks still pending at budget exhaustion end
  the loop **non-converged** with a named "checks pending" status line —
  never a hang, never a silent pass. Recovery is free: the next run's resume
  fast path re-polls. `STALE` runs read as pending; an empty rollup is
  vacuously green; an empty required set (branch protection requiring nothing)
  gets no special handling — it is the repo's configuration, not the gate's.
- **One atomic read**: head SHA, rollup states, and per-check required-ness
  (`CheckRun.isRequired(pullRequestNumber:)` — verified live) come from a
  single GraphQL query, so the head cannot move between the SHA read and the
  state read.
- **The readiness claim carries check state**: the playbook-composed status
  line appends the checks verdict (`; checks green` / `; checks red: cargo` /
  `; checks pending: cargo, devshell`) — byte-identical when the gate is off —
  and `Outcome` gains `checks: ChecksSnapshot?` (`green|red|pending|off|unknown`
  plus failing/pending check names; nil from `review`). A failed final
  snapshot read (2 bounded retries) degrades to `state = "unknown"` with a
  log rather than failing finished work.
- **Issue's open questions answered**: pending-at-budget ends non-converged
  (keeps "converged" truthful); check findings scope to head state, not
  authorship — a failure on a commit the loop did not produce files a finding
  too, since the PR is unmergeable either way and the loop's machinery is the
  repair path.
- **`maxIterations` default 8 → 10**: check-fix cycles consume loop units like
  review-fix cycles; the one deliberate gate-off behavior change, named in the
  migration note.
- **No new facade verb**: a separate ensure-checks operation was rejected —
  sequential loops make stale convergence claims against each other's pushes
  and violate every-push-followed-by-a-pass (ADR 0008 records the rejection).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playbooks`: five requirement changes. **PR review-fix loop** — the boundary
  sentence is redrawn (executing repo gate commands stays forbidden; reading
  platform check state through the check gate is in when configured) and the
  `maxIterations` default moves to 10. **PR review instruction contract** —
  the documented boundary statement gains the check gate's carve-out.
  **PR review ledger** — findings gain `source` and `check` fields (tolerant
  read), the judge's ledger view excludes check findings, and the playbook
  becomes a finding writer alongside filing/reconciliation/verification.
  **PR review report** — the deterministic status line carries check state
  when gated. **PR review check gate** (new requirement) — the gate's config,
  consult points, poll budget, finding lifecycle, named outcomes, and
  judge-blindness, with scenarios drawn from the issue's acceptance criteria.

## Impact

- `playbooks/pr/playbook.luau` — the `checks` config surface with `M.new`
  validation; the GraphQL check read; snapshot/gate consult flavors with the
  clock-free poll loop; `reconcileChecks`; ledger fields with tolerant reads;
  judge-surface exclusion; the two convergence injection points and the
  restructured resume path; `ChecksSnapshot` on `Outcome`; status line.
- `playbooks/pr/README.md` — the environment-requirements boundary section is
  rewritten (platform check state in when gated, repo gate commands out), plus
  config docs, the dry-run interaction (red cannot close without a push — the
  loop honestly ends non-converged at the cap), the budget arithmetic
  (`maxIterations × pollBudgetMs` worst case), and the vacuous-required
  stance.
- `CONTEXT.md` — glossary entries: check, check finding, check gate, repo
  gate commands; the review-fix loop entry's convergence definition sharpens.
- `docs/adr/0008-*.md` — the boundary un-decision with the rejected
  alternatives (post-loop CI handling, wait-for-green gate, separate verb,
  judge-owned findings).
- Ledger comment JSON gains per-finding `source` and `check`; old ledgers read
  tolerantly (`source = "review"`) — no migration.
- No facade, factory, or stdlib API changes; the factory's
  `converged`-gating gains the stronger meaning for free.
- Resolves #36. Non-goals (recorded for follow-ups): prompt guardrails on fix
  turns — the improvisation that produced the probe commit / close-reopen on
  the evidence PR — and PR-head desync detection (the documented
  close/reopen reattach remains the recovery).
