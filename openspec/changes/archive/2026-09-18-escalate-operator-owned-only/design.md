## Context

Two escalation gates exist today. The openspec playbook probes the work
session after every judge-rejected pass and asks a typed judge whether
human input is required; the pr playbook asks when an open blocking
finding carries the judge's `needsHuman` flag, then adjudicates the human
answer into ledger mutations. The bar on both is permissive ("cannot
proceed without a human" — satisfied by a confirmation request), and the
pr side carries the trigger, adjudication session, answer grammar, and
decisions ledger machinery that 2026-09-17-escalate-only-blocking built.
Issue #20 found the machinery's spec hole: the resume fast path bypasses
the gate entirely. ADR 0005 records the decision this design implements;
the glossary entries (Operator-owned decision, Recoverable choice,
rewritten Escalation) already ride this branch.

## Goals / Non-Goals

**Goals:**

- One bar, stated in prompt copy: asks happen only for operator-owned
  decisions; confirmations and recoverable choices never interrupt.
- openspec: same mechanism (probe → predicate judge → ask/fail), reworded
  strings, plus a component-owned autonomy clause on every work prompt.
- pr: delete the ask and everything that serves it; `needsHuman` becomes
  a report-only pointer with today's restriction (open + blocking) and
  today's rendering.

**Non-Goals:**

- No change to `std.escalate` (the mechanism; the openspec playbook still
  uses it) or to the escalation-mechanism requirement.
- No new config surface (no `escalationAdditions`; the bar is structural,
  like the protocol layer).
- No change to the judge's typed schema beyond prompt wording — the
  `needsHuman` field and its persistence are untouched.
- No broadening of `needsHuman` to non-blocking/deferred findings (kept
  restricted by decision, issue #28).

## Decisions

**The bar lives in copy, not code.** The probe prompts, `humanPredicate`
strings, and the judge's `needsHuman` rule line are per-operation data
and one Rules line — no new mechanism, no new schema, no config. The
wording is component-owned (not configurable away), consistent with the
protocol layer of the instruction contract.
*Alternative*: a config field mirroring `blockingAdditions` — rejected;
it invites loosening the bar back toward interruption, and the goal is
fewer asks everywhere.

**openspec keeps the two-step probe.** The probe is the dead-end
detector: a genuinely stuck agent is *asked*, rather than depending on it
volunteering blockage. The probe prompt now instructs self-resolution
and names the exception (an operator-owned decision the agent has no
authority to take); the predicate now scores a confirmation-seeking probe
false, dropping it to the fix path. The autonomy clause is appended once,
in `drive()`, to every work prompt — one site, all three operations.

**pr: delete, don't narrow.** The loop never asks; the PR at merge time
is the human checkpoint. Deleted: `triggeringFindings`' ask role, the ask
call and its payload composition (answer grammar, session label, prose),
`runAdjudication` and its schema and retry bound, the decisions-record
writer, and both ask-failure error paths. Kept: `needsHuman` on
`LedgerFinding`, its tolerant legacy read, its persistence on filing and
reconciliation, its render on open findings' lines. The judge rule's
first sentence is reworded to the authority bar; its second sentence
(never flag deferred/non-blocking) stays.
*Alternative*: narrow the trigger to approach-level decisions — rejected;
it keeps the machinery that #20 showed cannot be kept correct, for a
value (mid-loop redirection) the PR checkpoint already provides at review
time.

**Resume path needs no fix (closes #20).** With no ask in the loop,
`hasOpenBlocking` driving the resume fix turn is the specified behavior:
a flagged finding is auto-fixed and its flag rides the report. #20's
suggested fix (route the resume path through the ask) is superseded; the
spec delta states the resume behavior explicitly so it is no longer a
hole.

**`accepted` becomes a legacy status.** Its only writer was the
adjudication path. The ledger type keeps the status (tolerant read of
existing ledgers; terminal; renders in the report's accepted section),
and no new transition writes it. The decisions record likewise: parsed
tolerantly if present, never written.

**Retired behaviors keep their scenario names.** openspec 1.13 has no
scenario-level removal — a MODIFIED requirement must carry every
scenario name the current spec has, and archive enforces the same. The
delta therefore keeps the historical scenario names ("Answer is
adjudicated before any fix turn", "Human escalation abort fails", …)
and rewrites their bodies as retirement statements. The names are
permanent anchors; a future change that renames them must remove the
whole requirement or carry them forward.

**Judgment-call observability is one clause, openspec only.** The
autonomy clause makes the agent note judgment calls in its pass output,
which the operation returns to the caller. pr gets no equivalent
instruction: its net is structural — every autonomous fix is a diff the
next delta review judges, and disagreements become findings; a fixer
prose note the loop discards would be ceremony.

## Risks / Trade-offs

- [Over-claiming agents flail to the cap instead of asking] → Accepted
  (ADR 0005): the probe still catches stated inability; cap failure is
  loud and carries the ledger/report. No guard added.
- [A wrong-but-plausible product guess passes the judge silently] →
  Mitigated, not eliminated: the autonomy clause surfaces the judgment
  call in the returned text (openspec); the pr report renders
  `needsHuman` for the reviewing human. The residual is the price of
  autonomy-first, and the PR checkpoint backstops pr entirely.
- [Consumers relying on pr mid-loop asks] → BREAKING; the report's flags
  and the merge-time review are the replacement. Consumers pin the prior
  tag to defer.
- [Adversarial wording drift — prompt copy is the whole bar] → The spec
  scenarios pin the semantics (confirmation-never-escalates,
  report-only flag, resume auto-fix), so a future rewording that moves
  the bar fails verification.

## Migration Plan

Single change, backward-compatible ledger reads; no deploy sequencing.
Rollback is reverting the commit (ledgers written meanwhile carry no
decisions and no new `accepted` findings, so the old code reads them
cleanly).

## Open Questions

(none)
