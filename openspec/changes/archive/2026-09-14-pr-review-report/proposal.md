## Why

The pr-review-loop's only human-facing comment is posted by the converged work session — but that session only ever saw the *last* review pass, so the comment reads as a thin delta review ("the changes since the last commit look fine") rather than the PR's review story. A reader cannot see what was found, what was fixed, or what was deliberately deferred. The loop's terminal artifact should be a full, readable PR review report.

## What Changes

- The playbook posts a **PR review report** comment (marked `<!-- ptah:pr-review-report -->`), edited in place across runs, on **every terminal outcome** — converged and non-converged (capped). An aborted ask still raises before a report is produced.
- The report is authored by a dedicated **reporter agent** and posted by the playbook through the library's GitHub transport. The reporter submits a **typed single-field result** (the report body), bounded-retried; exhaustion raises. The playbook prepends a **deterministic status line** read from the ledger (converged / open-blocking count), so the report's factual claim cannot be wrong.
- The report carries: the PR's intention, the resolved findings (one-line entries), open non-blocking findings, deferred findings, accepted findings, and a loop summary (iterations, discovery/last-reviewed SHA, families). A non-converged report leads with its open blocking findings.
- **BREAKING**: the converged work session no longer posts a comment — the "verdict comment" artifact is removed. The immediate-converge `pr-review:converge` work session (whose only job was posting) is removed.
- **BREAKING**: config gains a required `reporterAgent` handle and an optional `reporterSessionConfig`. A consumer that does not configure a reporter now fails `ptah check`.
- The ledger retains resolved findings as **one-line entries** (`id`, `title`, `family`, `fixCommit`) instead of collapsing them to a bare resolved count, so the report can list what was fixed. The resolved count is still tracked; the report caps its resolved list with an "…and N earlier" note while the ledger retains all entries.
- `outcome.report` is added (the posted report text: status line plus body); `outcome.verdict` keeps its current meaning (the final verdict text).
- The artifact and its vocabulary are renamed: **PR review report** replaces "verdict comment".

## Capabilities

### New Capabilities

<!-- none: all behavior lives under the existing playbooks capability -->

### Modified Capabilities

- `playbooks`: the *PR review loop playbook* requirement changes (report posting on terminal outcomes, required `reporterAgent` + `reporterSessionConfig`, `outcome.report`, removal of the verdict comment); the *PR review ledger* requirement changes (resolved findings retained as one-line entries, not collapsed to a count); a new *PR review report* requirement is added (the report's author, posting, content, status line, and failure contract).

## Impact

- `playbooks/pr-review-loop/playbook.luau` — reporter session + typed schema + prompt assembly; report comment create/edit transport; `converge` and the cap path produce a report; ledger reconciliation retains resolved entries; `Outcome` gains `report`; `Config` gains required `reporterAgent` and optional `reporterSessionConfig`; `pr-review:converge` removed.
- `playbooks/pr-review-loop/README.md` — report semantics, terminal-outcome coverage, config surface, migration notes.
- `CONTEXT.md` — new glossary term **PR review report**; retire "verdict comment".
- Consumers (identus-ws lineage) — must configure `reporterAgent`; the converged comment they relied on is replaced by the report.
- No spec change to `std/*`; the reporter reuses the existing typed-session and `std/gh` transport machinery.
