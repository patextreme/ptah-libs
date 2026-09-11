## Context

Both components end their convergence loops with a hard `error(...)` when
the escalation judge confirms human input is needed
(`factory-components/components/openspec/component.luau`, the shared
`drive` skeleton; `factory-components/components/pr-review-loop/
component.luau`, the inline loop). ptah 0.1.0 ships `ptah.ask`: a pause
that suspends only the calling coroutine (work sessions survive the ask,
verified against ptah source), with `{action="respond", text}` /
`{action="abort"}` results and four distinct pcall-catchable raises when
no provider serves the request. Two ptah behaviors constrain any library
use of ask (both verified against ptah source at `e1b9c8d` and the
installed binary):

- `ptah check`/`run` pre-flight lints literal `ptah.ask(` call sites over
  the entry **plus its literal-require graph** — a literal ask in a
  library file is a finding (exit 1) in any consumer environment where no
  provider resolves, dead branch or not.
- An aliased reference (`local ask = ptah.ask`) is not collected — a
  *documented residual* in ptah's lint source ("the runtime check is the
  source of truth"), not an accident to be fixed away. No supported
  best-effort/try-ask API exists, and the ask spec forbids scripts from
  selecting providers.

Decisions below were settled with the user in a grilling session; the
proposal records the agreed behavior.

## Goals / Non-Goals

**Goals:**

- Escalation pauses and resumes: ask when a provider serves, fail exactly
  as today otherwise (byte-identical error wording) — zero behavioral
  drift for provider-less consumers, zero new config surface.
- One shared mechanism (`std/escalate`) so the alias + pcall + outcome
  classification exists in exactly one file.
- Spec, README, and glossary stay coherent with the two-mode escalation
  vocabulary (ask / hard fail).

**Non-Goals:**

- Exposing ptah's agent-generated ACP session id in asks — blocked on
  [patextreme/ptah#20](https://github.com/patextreme/ptah/issues/20);
  asks show the ptah session label (what the run's rendered stream is
  keyed by) until that lands.
- Session transcripts, resume, or any on-disk inspection of headless
  sessions (upstream ptah concerns).
- Config-gating the ask (no `ask: boolean` field): the operator's provider
  selection is the gate.
- Changing the judge predicates, probe prompts, or anything else in the
  loop skeletons.

## Decisions

### D1: `std/escalate` is a best-effort transport behind an aliased ask

Shape: `escalate.ask({ prompt: string, details: string? }) -> Outcome`
where `Outcome = { status: "respond", text: string } | { status: "abort" } |
{ status: "unavailable", reason: string }` (one record type,
status-discriminated, for strict-mode friendliness).

Implementation: module-local `local askFn = ptah.ask` — deliberately
alias-indirected so it is not a literal call site — wrapped in `pcall`.
The four runtime raises (prohibited / no provider / provider failure /
EOF) classify to `unavailable` carrying the error message as `reason`;
`{action="respond"}` → `respond` with `text` verbatim; `{action="abort"}`
→ `abort`. The module carries a rationale comment quoting ptah's
"documented residual; the runtime check is the source of truth" note so
the alias reads as design, not accident.

- *Alternative (rejected)*: literal `ptah.ask` + pcall — runtime-graceful
  but the pre-flight finding still hard-fails every provider-less
  consumer's check and run; incoherent.
- *Alternative (rejected)*: literal call + require providers (documented
  breaking change) — forces every consumer to configure an ask channel
  for a library feature they may never hit.
- *Alternative (rejected)*: `os.getenv("PTAH_ASK") == "none"` pre-check —
  only detects the prohibited case (`--ask`, `[ask]`, TTY auto-detect are
  invisible to env); `pcall` already handles all four raises uniformly;
  would couple the library to an env var name. Skipped.

Escalation prompt *composition* (identity, label, probe text) stays in the
components — loop policy, not transport — mirroring how `session-config`
centralized application while components own their prompts.

### D2: Components keep the session open across the ask

The current error path closes the session first. The ask path instead
leaves the work session open (ptah keeps the subprocess alive across a
pending ask; verified against source) so the human's answer lands in a
session that still holds the blocking findings as context. The close
moves to the abort/unavailable failure path and the normal iteration end.

### D3: The answer is sent verbatim — no header, no framing, no notice

`session:prompt(answer.text)` exactly as the human typed it. The user
explicitly chose raw verbatim over composed framing (the loop-convention
iteration header is *not* prepended on this one prompt; the ask itself
carries no "your reply becomes a prompt" notice). Consequence: the human
is implicitly driving the agent — casual answers become bare prompts.
Accepted trade-off; the ask details carrying the full probe text (not a
200-char excerpt) is what makes an informed answer possible.

### D4: Iteration accounting unchanged — asks are inside iteration N

The ask happens where the `error(...)` was, inside the iteration; a
resumed iteration is the same iteration. `maxIterations` therefore bounds
the total loop including repeated ask→answer cycles that never satisfy
the judge ("did not converge" stays the honest terminal for a human whose
answers don't converge). No free iterations for human-blocking passes.

### D5: Failure wording is split, not replaced

- *unavailable* → today's strings byte-identical: openspec keeps
  `{sessionId}: human input is required (iteration N of M): {excerpt}`
  (200-char flattened excerpt); pr-review keeps
  `pr-review: human input is required to resolve the findings (iteration
  N of M)`. Provider-less consumers see zero drift.
- *abort* → new distinct wording `{prefix}: human aborted escalation
  (iteration N of M)` so logs distinguish "human refused" from "no channel
  existed".

### D6: Ask composition — identity line, label, full probe text

Prompt line: `{prefix} {per-call identity}: human input required
(iteration N of M)` — e.g. `openspec-groom add-auth: human input required
(iteration 2 of 10)` / `pr-review https://github.com/o/r/pull/42: human
input required (iteration 2 of 15)`. Attribution renders as
`ask {n} {script}` (script name only), so the identity line is what
disambiguates fan-out runs. Details: the work session's label
(`session:label()`, the id the rendered stream is keyed by) and the full
probe text. Exact line composition is implementation detail; the spec
pins identity + label + untruncated probe text.

### D7: `escalate` joins the package entry as `std.escalate`

`lib.luau` exports it beside `predicate`/`gh`/`daemon`/`sessionConfig`
(Package consumption requirement updated accordingly). Additive surface;
consumers' `ptah check` remains the compatibility gate.

## Risks / Trade-offs

- [The alias evades a safety lint deliberately] → The rationale comment
  in `std/escalate.luau` quotes ptah's documented-residual note; if ptah
  ever closes the residual (starts tracking alias-indirected asks), the
  pre-flight would start failing provider-less consumers and this design
  must be revisited — watch ptah releases; the fallback would be a
  supported try-ask API upstream (natural follow-on to ptah#20's issue
  family).
- [Human answers are unfiltered prompts into an agent with the user's
  authority] → Same trust boundary as the ask provider itself (the
  operator chose the channel); the loop's judge still gates every
  subsequent pass, and the cap bounds runaway loops.
- [Verbatim answers can be too terse for the agent to act on] → Accepted
  by design (D3); the details carry full probe text so the human *can*
  write an informed prompt. The loop re-judges the next pass regardless.
- [No timeout on asks — a forgotten terminal parks the run (and under a
  sequential daemon, everything)] → Inherent to `ptah.ask`; Ctrl-C is run
  cancellation (130/143) as for any pending operation. Documented in the
  README's ask notes; not fixable at this layer.
- [`--quiet` hides the session stream the label points at] → The ask
  itself always renders (ptah guarantee) and carries the full probe text,
  so the ask is self-contained even when the stream is suppressed.
- [Ask-answered iterations burn agent turns against the cap] → D4 is
  deliberate; a human hitting the cap sees the same "did not converge"
  error as the agent would.

## Migration Plan

Additive to consumers: new std export, no config changes, identical
failure behavior without a provider. No migration steps. Rollback is
reverting to the previous tag. Internally: archive
`move-factory-components` before this change so the stacked delta applies
to the main spec in order.

## Open Questions

- None blocking. The exact wording/format of the ask prompt line (D6) can
  be tuned during implementation without spec changes.
