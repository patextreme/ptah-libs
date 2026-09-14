# Design — PR review report

## Context

See `proposal.md` — Why. The current playbook's only human-facing comment is posted
by the converged work session inside `converge()` (`playbooks/pr-review-loop/playbook.luau`).
That session saw only the last review pass, so the comment is a delta review; the
discovery pass's full-PR prose is discarded when its session closes. Each iteration
creates a fresh session (`work:session({ id = "pr-review:{iteration}" })`), so no work
session holds the loop's history — the ledger comment is the only durable cross-pass
memory.

The ledger already demonstrates the transport this change reuses for the report: a
marker comment (`<!-- ptah:pr-review-ledger -->`) found by listing PR comments, then
created once and `PATCH`ed in place thereafter. The report is a second marker comment
with the same lifecycle.

## Goals / Non-Goals

**Goals:**

- A full, readable PR review report on every terminal outcome the operation returns.
- A status claim that cannot be wrong: composed by the playbook from ledger data.
- Retain enough resolved-finding detail in the ledger that "full report" is true.
- Remove the delta-shaped converged comment and the work session that produced it.

**Non-Goals:**

- Any change to the convergence mechanics, the judge, or the protocol fragment.
- Deterministic (non-agent) authoring of the report's prose.
- Multi-PR orchestration, non-GitHub hosts, or reading CI/gates (unchanged boundary).
- Any change under `std/*`; the reporter reuses existing typed-session and `std/gh`
  machinery.

## Decisions

**D1 — A dedicated, required reporter agent.** Config gains `reporterAgent` (required,
like `judgeAgent`) and `reporterSessionConfig` (optional, declared-order entries like
`judgeSessionConfig`). *Alternative:* fall back to the work or judge agent when unset
— rejected: an implicit reporter makes the report's authorship and model unpinnable
and hides a new required capability behind a default. Requiring it makes the break
explicit at `ptah check`.

**D2 — The reporter submits a typed single-field result.** The reporter session is
created with a `resultSchema` of `{ report: string }` (required, no additional
properties), bounded-retried exactly as the judge is. *Alternatives:* free prose (the
model prepends "Here is the report:" chatter the playbook would have to strip or
post verbatim); fully structured typed sections (over-constrains prose the reader is
meant to read). The retry loop mirrors `runJudge`; the two are close enough to share a
small typed-session helper in the module if it reads cleanly, but sharing is not
required by the specs.

**D3 — The playbook posts the report; the playbook owns the status line.** The
reporter returns the body; the playbook prepends a deterministic status line built
from the ledger — the outcome status and the open blocking count — then posts or edits
the marked comment through `std/gh`. *Alternative:* the reporter posts with its own
tooling — rejected: in-place edit needs the comment id, which the playbook already
tracks, and it would give the reporter PR-write access for no gain. Consequence: the
converged work session stops posting entirely; `buildVerdictPrompt` and the posting
half of `converge()` are removed.

**D4 — The ledger retains resolved findings with status `fixed`.** In `applyFindings`,
a finding the judge reconciled as resolved is no longer dropped; it keeps its fields
and takes status `fixed`, and `resolvedCount` still increments. The existing struct
carries everything needed (id, title, family, severity, validation, `fixCommit`), so
no field surgery is required and the retention is information-preserving. `fixed`
entries are skipped by reconciliation, `hasOpenBlocking`, and the open-findings
summary; they are terminal. *Alternative:* a separate resolved list — rejected as a
second representation of the same thing, with the same growth.

**D5 — The report runs on every returning terminal outcome.** Converged and capped
paths both produce a report; an aborted or unservable escalation raises before the
reporter runs. The immediate-converge fast path (existing clean ledger at the current
head) keeps its detection but loses its work session — `pr-review:converge` existed
only to post — and goes straight to the reporter. The in-loop convergence path closes
its review session, then reports.

**D6 — Report comment lifecycle and the outcome field.** The report comment uses
`<!-- ptah:pr-review-report -->`, found by listing comments and created once then
edited in place, mirroring the ledger transport. `outcome.report` carries the
**posted report text** (status line + body), so a caller can display the report
without re-reading the PR; `outcome.verdict` keeps its current meaning.

**D7 — Reporter context and the section contract.** The reporter prompt carries a full
ledger render (all findings grouped by status, including retained `fixed` entries,
plus intention, families, SHAs, resolved count, iteration state), the terminal status,
the last review pass's prose, and a required section list: *What this PR does*,
*Findings resolved*, *Open non-blocking*, *Deferred*, *Accepted*, *Loop summary*. For
a non-converged outcome the open blocking findings are a section as well, and the
status line leads. The resolved section is capped at a documented maximum (50) with an
"…and N earlier omitted" note; the ledger retains every entry. *Alternative:* hand the
reporter the raw JSON — rejected: it invites ledger-shaped output rather than a report.

**D8 — Reporter exhaustion raises.** After the bounded retries, the operation fails
with an error naming the reporter and attempt count, consistent with the judge. No
report is posted, and no outcome is returned. *Alternative:* return the outcome with
`report = nil` — rejected: it silently degrades the deliverable this change exists to
produce, and the ledger comment still preserves the terminal state.

**D9 — Naming.** The artifact is the **PR review report**; "verdict comment" is
retired across the spec, README, and `Config` doc comments. `outcome.verdict` is a
distinct machine concept and keeps its name. `CONTEXT.md` gains the term and drops the
old one; no ADR is warranted (reversible, and the rationale lives in this change).

## Risks / Trade-offs

- [An extra agent session now runs per terminal outcome] → `reporterSessionConfig` lets
  consumers pin a cheap model; the report is a rendering of typed ledger data, so a
  weak model is adequate.
- [Retained `fixed` entries grow the ledger on long PRs] → the report caps its resolved
  list; the ledger keeps every entry and a ledger that outgrows the platform limit
  fails loudly through the transport rather than truncating (unchanged behavior).
- [The reporter can omit or reorder sections] → the section contract states the
  required sections and the status line is deterministic; residual ordering is the
  reporter's editorial latitude, which is the point of choosing an agent.
- [`reporterAgent` required is a breaking config change] → migration notes name it
  explicitly; the previous tag is the rollback.
- [A re-run overwrites the previous report] → intended: the report is the PR's living
  summary, and edit-in-place is what makes re-runs idempotent rather than spammy.
- [Two playbook-written comments per PR now race under concurrent loops] → unchanged
  one-loop-per-PR environment requirement covers both comments.

## Migration Plan

1. Evolve the playbook in place; major version bump (breaking config + outcome shape).
2. Add `reporterAgent` (required) and `reporterSessionConfig`; add the reporter typed
   schema and prompt; remove `buildVerdictPrompt` and the posting half of `converge()`;
   drop the `pr-review:converge` session; add report read/create/update transport;
   retain resolved findings as `fixed` in `applyFindings`; add `outcome.report`.
3. Rewrite the README's converge phase, config surface, and migration notes; update
   `Config` doc comments; add **PR review report** to `CONTEXT.md`.
4. Consumer migration (identus-ws lineage): configure `reporterAgent`; read
   `outcome.report`; the converged comment is replaced by the report.
5. Offline test coverage stays out of scope here (the suite lives in the ptah
   repository); the new reporter schema, report transport, terminal-outcome coverage,
   and `fixed` retention need ptah-side coverage, tracked by the ptah adoption change.
6. Rollback: the previous playbook shape remains at the prior tag; consumers pin it.

## Open Questions

None. Remaining detail (exact status-line wording, the section contract's exact prose,
the report prompt's assembly) is implementation-level and pinned in the tasks.
