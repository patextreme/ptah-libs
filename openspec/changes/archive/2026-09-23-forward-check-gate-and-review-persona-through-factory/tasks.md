# Tasks

## 1. factory: config surface and forwards

- [x] 1.1 Add the two optional fields to the factory `Config` type with doc comments — `checks: prPlaybook.ChecksConfig?` (the composed review-fix loop's check gate; nil keeps the gate off, per the pr playbook's opt-in semantics) and `reviewInstruction: string?` (the review persona; nil selects the pr playbook's built-in default); verify `ptah check` accepts a config omitting both fields and type-errors a malformed `checks` table through the reused type
- [x] 1.2 At the single internal `prPlaybook.new` site, forward both fields verbatim — `checks = config.checks, reviewInstruction = config.reviewInstruction`; verify no other line changes and that unset fields reach the pr playbook as nil (no factory-side defaults, validation, or reshaping — D2/D3)
- [x] 1.3 Confirm the unset path is byte-identical: run a minimal `factory.new` + one-issue shim with neither field on a scratch repo and diff the review loop's behavior (gate off — zero check-state reads — and the default persona) against a pre-change run

## 2. Docs

- [x] 2.1 `playbooks/factory/README.md`: add the two entries to the config table (`checks` — optional, forwarded to the composed review-fix loop, nil = gate off; `reviewInstruction` — optional, the review persona, nil = built-in default), pointing at the pr playbook's docs for the gate's semantics and budget arithmetic rather than restating them; name the check gate in the review end-states prose (a converged report implies green checks when the gate is configured)
- [x] 2.2 Root `README.md`: add both fields to the factory example config (commented, like the other optional knobs); verify the example still parses as typed config against the updated `Config`

## 3. Verification and release

- [x] 3.1 Exercise the forwards end to end on a scratch repo (or lace-id-portal, the reporting consumer): a factory run with `checks = { scope = "all" }` consults check state at the convergence decision (pending devshell-style check → bounded poll, non-converged at budget exhaustion — the #97 incident shape, now impossible to miss); red checks surface as ledger findings the fix turn resolves; `reviewInstruction` visibly replaces the default persona in the review session prompt
- [x] 3.2 Record the upstream coverage obligations against the ptah test-suite tracking issue: factory-level `checks` forward (gate consulted, unset = off), `reviewInstruction` forward (persona applied, unset = default), and a config-typo case documenting the per-issue construction failure class (D3)
- [x] 3.3 At release: bump the minor version (new public config surface) per the README versioning contract; verify `pesde.toml` version and the README table agree
