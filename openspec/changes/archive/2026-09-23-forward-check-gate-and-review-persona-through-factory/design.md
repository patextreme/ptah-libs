# Design: forward the check gate and reviewer instruction through the factory

## Context

See `proposal.md` — Why for the incident and the composition-debt timeline.
The relevant current state:

- The factory builds its pr playbook instance at exactly one site, inside
  the per-issue closure (`playbooks/factory/playbook.luau:555`), forwarding
  `agent`, `judgeAgent`, `reporterAgent`, the three session-config entry
  lists, the per-issue `workingDir`, and `maxIterations` from
  `config.maxReviewIterations`. That last forward is the precedent this
  change extends: a scalar, optional, forwarded verbatim, no factory-side
  validation.
- The pr playbook already owns everything being forwarded:
  `checks: ChecksConfig?` (`scope`/`pollBudgetMs`/`pollIntervalMs`,
  validated field-by-field in its `new` — `pr-review:`-prefixed errors),
  gate off when the table is absent, and `reviewInstruction: string?`
  falling back to the built-in default persona when nil. The #36 spec
  requirements cover the gate's semantics end to end; nothing on the pr
  playbook side changes here.
- ADR 0006 rules the composition: factory config is data only, no playbook
  instances. Both new fields are data (a table of three scalars, a string),
  so the passthrough is exactly the shape the ADR invites — the consumer
  cannot reach the internal instance, and `Config` is the only possible
  surface.

No code outside `playbooks/factory/` changes. That is the whole point: this
is re-wiring composition debt, not designing a mechanism.

## Goals / Non-Goals

Goals: a factory-driven `reviewFixLoop` can gate on check state (converged
implies green); a repo's review persona survives migration from hand-rolled
orchestration to the factory; unset fields are byte-identical to today; the
factory adds no semantics of its own — no defaults, no renames, no
re-validation.

Non-goals:

- **The composition-layer default** (factory defaulting the gate on, e.g.
  `scope = "required"`): deliberately deferred by the issue. The pr playbook
  made the gate opt-in — "behavior unchanged" when nil — and a factory
  default would make the composition *more* eager than the thing it
  composes. Recorded under Open Questions; not decided here.
- **`blockingAdditions` passthrough**: the third pr-playbook data knob with
  no factory surface, and the issue scopes this change to the two named
  fields. It rides the identical pattern later on demand (see D5).
- **Factory outcome changes**: `pr-reviewed`/`pr-non-converged` keep their
  verdict-shaped hand-off. The checks snapshot stays a pr-playbook outcome
  concern; a human reads check state from the PR review report's status
  line, as #36 intended. Factory `Outcome` API growth is not asked for.
- **Persona/fragment composition**: `conventions` and `prContract` belong to
  the direct-edit and delivery prompts; the persona belongs to the review
  sessions. One consumer text per prompt family, no cross-injection.
- **`dryRun` passthrough**: the spec forbids it ("The factory SHALL expose
  no dry-run pass-through"). Unchanged.

## Decisions

### D1. Verbatim passthrough — the `maxReviewIterations` precedent, extended

Two optional `Config` fields, same names as the pr playbook's
(`checks`, `reviewInstruction`), forwarded at the single internal
`prPlaybook.new` site. One-line forwards; no transformation anywhere.

Alternatives rejected:

- *A factory-level alias vocabulary* (`reviewChecks`, `reviewPersona`, …):
  two names for one thing across a verbatim-forward boundary invites drift
  and grep misses. A consumer reads the pr playbook's docs to configure the
  gate; the factory config should use the same words.
- *A nested `review = { checks = …, instruction = … }` group*: prettier
  grouping, but it re-shapes what is forwarded, needs its own nil rules
  (empty table vs nil), and buys nothing — the factory has exactly two
  review knobs to expose; a group is structure for its own sake.
- *Constructing the pr playbook once at `factory.new`*: impossible without
  breaking the per-issue `workingDir` (each issue's instance is bound to its
  worktree). Not a real alternative; recorded so nobody "simplifies" the
  forward site into it later.

### D2. Nil semantics owned by the pr playbook

The factory forwards the fields and nothing else: nil `checks` reaches the
pr playbook as nil (gate off — the pr playbook's own opt-in semantics, no
factory-added default), nil `reviewInstruction` reaches it as nil (built-in
default persona via the pr playbook's own fallback). Unset behavior is
therefore identical by construction, not by careful reimplementation.

The deferred question stays deferred: *should the factory default the gate
on?* That would be a composition-layer policy — the factory deciding that
its review loop is stricter than the pr playbook's default. It deserves its
own decision (and arguably an ADR, since it reverses a piece of the opt-in
philosophy), not a rider on a passthrough change.

### D3. Validation stays where it lives

The pr playbook validates `checks` field-by-field in its constructor; the
factory adds no validation of its own. Consequence, named and accepted: the
pr playbook is constructed per-issue (after claim and worktree
provisioning), so a malformed `checks` table fails the *first issue* —
failed outcome, logged, claim marker kept, drain continues and every
subsequent issue fails identically — rather than raising at `factory.new`.

- This is the established failure class: a bad `maxReviewIterations` behaves
  the same way today. Consistency with the precedent is worth more than a
  fail-fast `factory.new` that the precedent never had.
- *Factory-side re-validation rejected*: it duplicates the pr playbook's
  validation (two places to update when `ChecksConfig` grows — drift risk)
  to save one loud, immediate, per-issue failure. If it bites in practice,
  adding `factory.new` validation later is additive and breaking nothing.
- Error prefix in factory-run logs is `pr-review:` for these fields, as it
  already is for loop-level failures. Grep-by-`factory:` purists lose
  nothing new.

### D4. Type surface: reuse, don't re-export

The factory's `Config` types the field as `prPlaybook.ChecksConfig?` — the
module is already required for the construction. No copy of the type, no new
exported alias, no wrapper. A consumer configuring `checks` is really
configuring the pr playbook; there is one type and it lives where the
semantics live. (`reviewInstruction` is `string?` in both places.)

### D5. `blockingAdditions` stays out, named

The third unforwarded data knob. Excluded because the issue scopes this
change to two fields and bundling a third expands review scope without a
driver; included-in-reasoning here so its absence reads as a decision, not
an oversight. The pattern is D1 verbatim; a follow-up issue is a ten-line
change identical in shape.

## Risks / Trade-offs

- [Config typo surfaces mid-run, not at construction] → accepted (D3): the
  failure is loud, immediate on the first issue, and self-evident (every
  issue fails identically with the same `pr-review:` message). Escape hatch:
  factory-side validation can be added later without breaking anything.
- [Composition surface grows by two fields] → mitigated by the fields
  carrying zero factory semantics: the factory README's entries point at the
  pr playbook's documented behavior rather than restating it.
- [Reviewer-instruction quality problems are now reachable from the factory]
  → they were already reachable by hand-rolled orchestration; nothing new is
  possible, only easier. The glossary's guidance stands: a long or
  repo-pinned persona points at a versioned document rather than inlining
  text.

## Migration Plan

1. Land with both fields optional and unset-by-default — behavior identical
   for every existing consumer; no migration note required (unlike #36,
   nothing defaults differently).
2. Consumers opt in per repo: add `checks` to reach the gate (start with
   `scope = "all"` if branch protection required-ness is uncertain,
   `"required"` once verified) and/or `reviewInstruction` to carry the
   persona that previously lived in the hand-rolled shim; then delete the
   hand-rolled orchestration.
3. Rollback: drop the fields. No persisted state, no ledger migration — the
   gate's own state lives in the pr playbook's ledger and reads the same
   whether reached through the factory or directly.

## Open Questions

- **Composition-layer gate default** (explicitly out of scope per the
  issue): should `factory.new` default `checks` on (e.g.
  `scope = "required"`, vacuously green when a repo requires nothing)? This
  is the one philosophical fork — the pr playbook chose opt-in, and a
  default here would make the factory the stricter composition. If pursued,
  it wants its own issue and likely an ADR (it reverses a piece of #36's
  recorded philosophy at the composition layer).
