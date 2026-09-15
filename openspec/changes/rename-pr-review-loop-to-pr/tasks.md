## 1. Rename the playbook module

- [ ] 1.1 `git mv playbooks/pr-review-loop playbooks/pr` and update `lib.luau` (require path `./playbooks/pr/playbook`, export key `pr`); verify `grep -rn "prReviewLoop" lib.luau playbooks/` returns nothing and `git status` shows the rename, not delete+add
- [ ] 1.2 Confirm the wire/prefix freeze: `git diff` on `playbooks/pr/playbook.luau` shows no changes to the marker strings (`ptah:pr-review-ledger`, `ptah:pr-review-report`), the `pr-review:` error/ask prefixes, or session-id prefixes

## 2. Documentation

- [ ] 2.1 Update `README.md` (export table row, playbook index entry) and `playbooks/README.md` (index entry, `pr-review-loop/default-instruction.luau` path mention) to `pr` / `playbooks/pr/`; verify `grep -rn "pr-review-loop\|prReviewLoop" README.md playbooks/README.md` returns only intentional historical/migration mentions
- [ ] 2.2 Add a short breaking-reshape migration section to `playbooks/pr/README.md` naming the single consumer edit (`prReviewLoop` → `pr` in the shim) and the pin-prior-tag deferral; verify it matches the identus-ws-lineage section's shape

## 3. Validation

- [ ] 3.1 Write a scratch consumer shim (in /tmp, not the repo) that requires `lib.luau` and reads the `pr` export; run `ptah check` on it; verify it type-checks and that referencing `prReviewLoop` in the shim reports a type error naming the field

## 4. Land the spec delta

- [ ] 4.1 Run `openspec validate rename-pr-review-loop-to-pr --strict` and verify it passes; then sync/archive the change per the openspec workflow so `openspec/specs/playbooks/spec.md` names `pr` in the export surface
