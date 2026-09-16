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

Worse, issue #13 documents the sibling failure for *legitimately* triggered asks:
the human's answer never reaches the ledger structurally. The answer goes verbatim
into the work session as a fix prompt; `applyFindings` — the only writer of finding
status — runs solely on the review→judge path. A maintainer decision ("defer f1")
lives in prose only, the ledger keeps the finding `open`/`blocking`, and a fresh
session with no memory of the answer "resolves" it the obvious way — PR #12's loop
deleted the file the human had twice said to keep, then reported converged with
"Deferred: None". ~88 minutes wall clock, four of ten iterations, and a maintainer
decision inverted.

## What Changes

- **Escalation trigger narrowed**: the loop asks a human only when a finding that
  gates convergence — `open` + `blocking` — carries `needsHuman`. The judge's
  `needsHuman` flag on non-blocking or deferred findings no longer triggers an ask;
  those findings surface in the review prose and the posted report.
- **Recurrence-path join**: `priorFindingsStatus` records carry no severity, so the
  trigger joins each record's id against the ledger and escalates only when the
  referenced finding is itself `open` + `blocking`. An unknown id (judge
  hallucination, stale ledger reference) never escalates.
- **Typed adjudication of answers**: on an answered ask, a typed adjudication
  session (the judge agent under a dedicated result schema) converts the verbatim
  answer into per-finding ledger mutations — `defer` (open → deferred), `accept`
  (open → accepted), `fix` (the answer directs the fix) — each with an optional
  note, before any fix turn. Mutations target existing open findings only; unknown
  or terminal ids are no-ops; adjudication never creates findings.
- **Conditional fix turn**: a `fix` mutation sends the answer verbatim to the
  still-open work session followed by commit-and-push; a decision-only answer issues
  no session prompt and no push. A decision-only adjudication that leaves no open
  blocking findings converges immediately — no empty-delta review pass.
- **`decisions` ledger record**: every answered ask records its prompt line, the
  verbatim answer, and the applied mutations in the ledger. Decided findings clear
  their persisted `needsHuman` flag and render in the report as maintainer decisions
  — the truthful counterpart to #13's false "Deferred: None".
- **Ask payload names its subject**: the prompt line names every triggering finding
  (id, family, severity, title); the details teach the answer grammar
  (`defer <id>`, `accept <id>`, `fix: <instructions>`) ahead of the session label,
  ACP session id, and full review prose.
- **Persist `needsHuman` in the ledger**: `LedgerFinding` gains a `needsHuman` field,
  recorded when the finding is filed and updated when a later reconciliation revisits
  it, cleared when a decision lands. The report is the durable channel for
  human-worthy non-blocking concerns that no longer ask.
- **Deferred dedup**: the ledger summary shown to the judge lists deferred findings
  with their ids; the judge's reconciliation gains a still-deferred outcome so a
  recurring deferred concern is reported against the existing id instead of being
  refiled as a duplicate. Deferred stays terminal — no exits; a deferred concern
  that becomes in-scope again is correctly filed as a new open finding.
- **Judge prompt hardened**: the rules state that `needsHuman` is meaningful only on
  open blocking findings, direct human-worthy non-blocking concerns to the prose, and
  cover the deferred-recurrence vocabulary. The code predicate remains the guarantee;
  the prompt reduces noise.
- **BREAKING** (behavioral): consumers that relied on an ask firing for non-blocking
  `needsHuman` findings no longer get one; the answer always reaches the work
  session verbatim — now only when adjudication requests a fix. No config or API
  surface is removed; the ledger JSON gains fields (`needsHuman`, `decisions`).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playbooks`: two requirements change. **PR review loop playbook** — the escalation
  trigger is gated on `open` + `blocking` findings; the ask names its triggering
  findings and answer grammar; answered asks are adjudicated into typed ledger
  mutations with a conditional fix turn and an immediate-converge short-circuit for
  decision-only outcomes; the judge contract's reconciliation vocabulary grows a
  still-deferred outcome. **PR review ledger** — a finding record carries a
  `needsHuman` flag (updated on reconciliation, cleared on decision); the ledger
  gains a `decisions` record (prompt line, verbatim answer, applied mutations);
  decided findings render in the report as maintainer decisions.

## Impact

- `playbooks/pr/playbook.luau` — `anyNeedsHuman` becomes the gated predicate (join
  against the ledger for the reconciliation half); a new adjudication session type
  with its result schema and bounded retry; the respond branch rewires to
  adjudicate-then-conditionally-fix; `applyFindings` records/updates/clears
  `needsHuman` and applies adjudication transitions; the decisions record persists;
  `ledgerSummary` lists deferred findings; the ask payload names findings and the
  grammar; `renderFinding` shows the flag and the maintainer-decision annotation;
  judge prompt rules.
- `playbooks/pr/README.md` — the Escalate section and the trigger description.
- `openspec/specs/playbooks/spec.md` — the two requirement texts and their scenarios
  (via this change's delta).
- Ledger comment JSON gains a per-finding boolean and a `decisions` array; old
  ledgers without them are read tolerantly (`needsHuman` false, no decisions — no
  migration needed).
- Resolves #13's items 1–4 (adjudication, decisions record, ask payload, conditional
  push); items 5–6 (general empty-delta short-circuit, `fixCommit` attribution)
  remain non-goals.
- Non-goals, recorded for follow-ups: transitions *out of* `deferred`, per-finding
  fix attribution in `recordFixCommit`, the general empty-delta pass short-circuit,
  and the ptah-side offline suite update (the library ships no test suite; the
  coverage contract lives in the ptah repository).
