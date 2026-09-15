--!strict
-- The pr-review-loop protocol fragment: component-owned instruction text
-- appended to every review prompt at runtime, after the persona and
-- before the phase directive. Data only — content, not logic: no config,
-- no runtime handles, no requires. It carries the convergence mechanics a
-- persona replacement must not be able to strip — delta-review rules, the
-- in-session validation directive, recurrence reporting by ledger id, and
-- family reuse-or-justify guidance. See README.md (the three-layer
-- instruction contract).

return [==[
## Review protocol (non-negotiable)

These rules are part of the loop's mechanics and apply regardless of the persona above.

- **Validate blocking findings before finalizing.** For every finding you would report as blocking, validate it with a subagent before you finalize the review: spawn a subagent to independently check whether the issue is real. Drop the findings that do not survive validation, and state the validation outcome (validated or refuted) for each finding you keep.
- **Review only the delta when a last-reviewed commit is given.** The ledger data below names the last reviewed commit. When it is present, review only the changes made since that commit — do not re-review the rest of the pull request. When no last-reviewed commit is given, review the entire pull request.
- **Report recurrences by ledger finding id.** If an issue you find is a recurrence of a finding already recorded in the ledger, report it against that finding's id rather than filing a new finding. File a new finding only for an issue the ledger does not already represent.
- **Reuse a family name, or justify a new one.** Findings are grouped into families. When a finding belongs to a family already listed in the ledger, use that exact family name. Introduce a new family name only when no existing family fits, and say why.
]==]
