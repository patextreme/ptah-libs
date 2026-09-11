## Why

Both convergence-loop components (openspec, pr-review-loop) terminate the
entire run with an error the moment a judge confirms a blocker needs human
input — the only way forward is for a human to read the error, intervene
out-of-band, and rerun from scratch. ptah now provides `ptah.ask`: a pause
that suspends only the calling coroutine (sessions survive, the run stays
alive), with distinct pcall-catchable raises when no ask provider exists.
Escalation can therefore become a pause-and-resume — the run asks the
human, their answer flows back into the still-open work session, and the
loop converges instead of crashing — while provider-less environments keep
today's failure behavior byte-for-byte.

## What Changes

- **New stdlib module `std/escalate`** (exported from the package entry as
  `std.escalate`): a best-effort ask transport. One call, `ask({ prompt,
  details? })`, returns a status-discriminated outcome — `respond` (with
  the answer text), `abort` (the human refused), or `unavailable` (with the
  provider failure reason; ptah's four distinct ask raises classified).
  Implemented through an aliased `ptah.ask` reference behind `pcall` so a
  library-level ask never trips ptah's literal-call-site pre-flight lint
  (the alias is a documented residual in ptah's lint; the runtime raise is
  the source of truth) and never blocks a consumer's `ptah check`/`run`.
- **Both components' escalation branch** becomes: probe → judge confirms
  human input required → `escalate.ask`:
  - **respond** — the work session stays open across the ask and the
    answer text is sent **verbatim** as the session's next prompt (no
    header, no framing); the loop then continues normally (for
    pr-review-loop the commit-and-push step still follows a human-guided
    fix; the iteration counts against `maxIterations`).
  - **abort** — the operation fails with a new, distinct error:
    `{prefix}: human aborted escalation (iteration N of M)`.
  - **unavailable** — the operation fails with today's error wording,
    byte-identical (openspec keeps its 200-char probe excerpt;
    pr-review-loop keeps its current form).
- **Ask composition** (owned by the components, not std): the prompt line
  carries the per-call identity (`openspec-groom add-auth: human input
  required (iteration 2 of 10)` / `pr-review <pr-url>: ...`); the details
  carry the work session's label (correlatable with the run's rendered
  stream) and the **full probe text** (no truncation — the human must be
  able to answer).
- **No config-surface changes**: asking is the default escalation mode,
  best-effort by construction — the operator's ask-provider selection
  (`--ask` / `PTAH_ASK` / `[ask]` / TTY auto-detect) is the opt-in, and a
  provider-less environment behaves exactly as today.
- **Documentation**: the library README's loop conventions gain the
  two-mode failure wording (ask / hard fail) and ask behavior notes
  (concurrent asks serialize FIFO; a pending ask keeps the run alive;
  `--quiet` hides the session stream but asks still render); both
  component READMEs describe escalation behavior including the note that
  an unresolvable task scope can surface as an ask; CONTEXT.md sharpens
  the *Convergence loop* entry and adds an *Escalation* term (one routing
  decision, two realizations).
- **Out of scope**: displaying the agent-generated ACP session id in the
  ask (ptah does not expose it to scripts today) — deferred until
  [patextreme/ptah#20](https://github.com/patextreme/ptah/issues/20)
  resolves; session transcripts/resume are upstream ptah concerns.

## Capabilities

### Modified Capabilities

- `factory-components`: the escalation behavior of the openspec and
  pr-review-loop components changes from fail-fast to best-effort ask
  (respond continues the loop with the verbatim answer; abort and
  provider-unavailable fail with distinct vs byte-identical wordings), a
  new stdlib escalation-mechanism requirement is added, and the package
  entry's export surface gains `std.escalate`. Note: this capability's
  spec currently exists only as the un-archived delta of
  `move-factory-components`; this change's delta stacks on that delta —
  archive `move-factory-components` first.

## Impact

- **Code**: new `factory-components/std/escalate.luau`; modified
  `factory-components/components/openspec/component.luau` (the shared
  `drive` skeleton), `factory-components/components/pr-review-loop/
  component.luau` (the inline loop's escalation branch), `lib.luau` (new
  `std.escalate` export).
- **Consumers**: additive — a new std export; no config field changes
  (verified by `ptah check` on consumer shims as the compatibility gate).
  Behavior changes only where an ask provider resolves (interactive runs
  now pause instead of failing at escalation).
- **Docs**: `factory-components/README.md` (loop conventions),
  `components/README.md` (stdlib listing),
  `components/{openspec,pr-review-loop}/README.md`, `CONTEXT.md`.
- **Verification**: `ptah check` on a consumer-style shim (this repository
  ships no test suite; offline coverage lives in the ptah repository per
  the Offline test coverage requirement).
