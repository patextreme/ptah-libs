## Why

The pr-review loop escalates to a human when the judge flags `needsHuman` on **any**
finding, while the loop's own convergence predicate is `open + blocking`. A deferred,
non-blocking finding can therefore interrupt a human, preempt the batched fix turn
for a mechanically fixable blocking finding, and — with no ask provider — fail the
whole operation. PR #14's review run demonstrated all of it: a deferred scope note
(`f4`, "does the factory script belong?") triggered the ask while the blocking
spec-sync finding waited for a mechanical fix, and the answered ask's decision could
not be recorded anywhere in the ledger. Escalation is a convergence-gating
instrument; its trigger must be a subset of the convergence predicate, not an
independent flag over all findings.

## What Changes

- **Escalation trigger narrowed**: the loop asks a human only when a finding that
  gates convergence — `open` + `blocking` — carries `needsHuman`. The judge's
  `needsHuman` flag on non-blocking or deferred findings no longer triggers an ask;
  those findings surface in the review prose and the posted report.
- **Recurrence-path join**: `priorFindingsStatus` records carry no severity, so the
  trigger joins each record's id against the ledger and escalates only when the
  referenced finding is itself `open` + `blocking`. An unknown id (judge
  hallucination, stale ledger reference) never escalates.
- **Persist `needsHuman` in the ledger**: `LedgerFinding` gains a `needsHuman` field,
  recorded when the finding is filed and updated when a later reconciliation revisits
  it, rendered in the report's finding lines. The report becomes the durable channel
  for human-worthy non-blocking concerns that no longer ask.
- **Deferred dedup**: the ledger summary shown to the judge lists deferred findings
  with their ids; the judge's reconciliation gains a still-deferred outcome so a
  recurring deferred concern is reported against the existing id instead of being
  refiled as a duplicate. No transitions out of `deferred` are added — a deferred
  concern that becomes in-scope again is correctly filed as a new open finding.
- **Judge prompt hardened**: the rules state that `needsHuman` is meaningful only on
  open blocking findings, direct human-worthy non-blocking concerns to the prose, and
  cover the deferred-recurrence vocabulary. The code predicate remains the guarantee;
  the prompt reduces noise.
- **BREAKING** (behavioral): consumers that relied on an ask firing for non-blocking
  `needsHuman` findings no longer get one; those concerns move to the report. No
  config, API, or ledger-consumer surface is removed — the ledger JSON gains a field.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playbooks`: two requirements change. **PR review loop playbook** — the escalation
  trigger is gated on `open` + `blocking` findings (new scenarios: escalation not
  raised for non-blocking/deferred `needsHuman`; unknown reconciliation ids never
  escalate; deferred recurrences reconcile against the existing id), and the judge
  contract's reconciliation vocabulary grows a still-deferred outcome. **PR review
  ledger** — a finding record carries a `needsHuman` flag, updated on
  reconciliation, surfaced in the PR review report's finding lines.

## Impact

- `playbooks/pr/playbook.luau` — `anyNeedsHuman` becomes the gated predicate (join
  against the ledger for the reconciliation half), `applyFindings` records and
  updates `needsHuman`, `ledgerSummary` lists deferred findings, the judge prompt
  rules, `renderFinding` shows the flag.
- `playbooks/pr/README.md` — the Escalate section and the trigger description
  (`needsHuman` is the loop's only escalation trigger → only on open blocking
  findings).
- `openspec/specs/playbooks/spec.md` — the two requirement texts and their scenarios
  (via this change's delta).
- Ledger comment JSON gains a per-finding boolean; old ledgers without the field are
  read as `needsHuman = false` (reading is tolerant; no migration needed).
- Non-goals, recorded for follow-ups: transitions out of `deferred` (e.g.
  `deferred → accepted`), per-finding fix attribution in `recordFixCommit`, and the
  ptah-side offline suite update (the library ships no test suite; the coverage
  contract lives in the ptah repository).
