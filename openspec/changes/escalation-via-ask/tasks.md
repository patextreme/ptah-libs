## 1. std/escalate module

- [x] 1.1 Create `factory-components/std/escalate.luau` (`--!strict`): module-local aliased `local askFn = ptah.ask` with the rationale comment quoting ptah's documented-residual note (design D1), `ask({ prompt, details? }) -> Outcome` wrapping `askFn` in `pcall`, classifying `{action="respond"}` → `{status="respond", text}`, `{action="abort"}` → `{status="abort"}`, and every raise → `{status="unavailable", reason=<error message>}`; export the `Outcome` type. Verify: `ptah check` on a scratch shim requiring the module passes with no ask-related finding and no provider configured (stdin redirected from /dev/null)
- [x] 1.2 Exercise the classification paths off-line: with `PTAH_ASK=none ptah run` the ask returns `unavailable` (pcall catches the prohibited raise); with `PTAH_ASK=stdin` and a line piped in it returns `respond` carrying the line; with `PTAH_ASK=stdin` and EOF it returns `unavailable` (EOF raise). Verify: a scratch shim printing the three statuses exits showing each expected status

## 2. openspec component

- [x] 2.1 In `factory-components/components/openspec/component.luau`, replace the `drive` skeleton's `needsHuman` failure with escalation via `std/escalate`: compose the ask prompt line `{sessionId} {change}: human input required (iteration N of M)` (change threaded through `drive`'s opts), details carrying `session:label()` and the **full** probe text; on `respond` keep the session open, `session:prompt(answer.text)` verbatim (no header), close the session at the iteration end as the normal path does, and let the loop continue; on `abort` close and `error("{sessionId}: human aborted escalation (iteration N of M)")`; on `unavailable` close and `error` with today's byte-identical string including the 200-char excerpt. Verify: `ptah check` on a consumer-style shim using the component passes
- [x] 2.2 Keep all other loop behavior identical: probe prompt, judge predicate, resolve prompt, per-iteration session ids/config application, and the cap error. Verify: diff-review of `drive` confirms the only changes are the escalation branch and threading the identity string; iteration numbering unchanged (ask-resumed pass is iteration N, cap still bounds the loop)

## 3. pr-review-loop component

- [x] 3.1 In `factory-components/components/pr-review-loop/component.luau`, replace the `needsHuman` failure in `review` with escalation via `std/escalate`: ask prompt line `pr-review {prUrl}: human input required (iteration N of M)`, details carrying `session:label()` and the full probe text; on `respond` keep the session open, `session:prompt(answer.text)` verbatim, then run the existing push prompt (when not dry-run) and continue the loop; on `abort` close and `error("pr-review: human aborted escalation (iteration N of M)")`; on `unavailable` close and `error` with today's byte-identical string. Verify: `ptah check` on a consumer-style shim using the component passes

## 4. Package entry

- [x] 4.1 Export the module from `lib.luau` as `std.escalate` beside the existing std exports. Verify: `ptah check` on a scratch shim asserting `std.escalate.ask` is callable via the entry, and grep confirms the export table lists `escalate`

## 5. Documentation

- [x] 5.1 Update `factory-components/README.md`: stdlib listing gains `escalate`; the Loop conventions section gains the two-mode failure wording (ask / hard fail, with the abort and unavailable wordings) and the ask behavior notes (concurrent asks serialize FIFO, a pending ask keeps the run alive, `--quiet` hides the stream but asks always render, no ask timeout). Verify: the section names both failure wordings and all four ask notes
- [x] 5.2 Update `factory-components/components/README.md` stdlib listing and the openspec + pr-review-loop component READMEs: escalation behavior (three outcomes), ask composition (identity, label, full probe text), and the note that an unresolvable implement scope can surface as an ask rather than an immediate error. Verify: each README's operations section describes the ask-and-resume path
- [x] 5.3 Update `CONTEXT.md`: sharpen the *Convergence loop* entry ("escalates to a human" now means ask-when-served / fail-otherwise) and add an *Escalation* entry (the routing decision and its two realizations, ask and hard fail). Verify: both entries present, no implementation detail in the glossary
- [x] 5.4 Record the deferral: note in the pr-review-loop and openspec READMEs (or the library README's ask notes) that asks display the ptah session label and that agent-side ACP session-id display is deferred pending [patextreme/ptah#20](https://github.com/patextreme/ptah/issues/20). Verify: the note links the issue

## 6. Verification

- [x] 6.1 Write a throwaway consumer-style shim (not committed) driving `openspec` and `prReviewLoop` with inline agent specs, run `ptah check` on it with no ask provider configured (stdin from /dev/null), and confirm zero ask-related findings — the compatibility gate proving provider-less consumers are unaffected. Verify: check exits clean of ask findings
- [x] 6.2 Run the openspec CLI validation: `openspec validate --change escalation-via-ask` passes (delta structure, scenario format)
