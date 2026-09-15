## Why

Playbooks are moving to entity naming — `pr`, `issue`, `openspec` — each a
facade of its entity's verbs, so a new operation joins an existing facade
instead of spawning a new capability-named playbook (recorded in
`docs/adr/0001-name-playbooks-for-entities.md`). The `issue` playbook is
next; this rename lands first so it inherits the final naming rather than
inheriting a rename.

## What Changes

- **BREAKING**: the library export `prReviewLoop` becomes `pr` in
  `lib.luau`. No alias: consumers pin the prior tag to defer the break
  (the repo's established migration ritual).
- **BREAKING**: the playbook directory `playbooks/pr-review-loop/`
  becomes `playbooks/pr/` (module path `playbooks/pr/playbook.luau`).
- The spec's package-consumption requirement changes to name `pr` in the
  export surface (`prReviewLoop` disappears).
- Documentation follows the rename: the library README's export table and
  playbook index, `playbooks/README.md`, and the playbook's own README.
- **Explicitly unchanged**: the persisted wire markers
  (`<!-- ptah:pr-review-ledger -->`, `<!-- ptah:pr-review-report -->`),
  the user-visible `pr-review:` error/ask prefixes, and all session-id
  prefixes — persisted state on third-party infrastructure is frozen
  while code-level identifiers rename (ADR 0001).
- Migration notes section added to the playbook README (breaking-reshape
  section, matching the identus-ws-lineage precedent).

## Capabilities

### New Capabilities

(none — this change renames; it adds no behavior)

### Modified Capabilities

- `playbooks`: the "Package consumption" requirement's export surface
  changes — `prReviewLoop` is replaced by `pr`. No requirement of the PR
  review loop itself changes; the loop's behavior is byte-stable.

## Impact

- `lib.luau` — the re-export table (`prReviewLoop` → `pr`).
- `playbooks/pr-review-loop/` → `playbooks/pr/` — directory rename;
  internal `require` paths from `lib.luau` only (the playbook's own
  relative requires into `std/` are unaffected by its directory name).
- `README.md`, `playbooks/README.md` — export table, playbook index.
- `openspec/specs/playbooks/spec.md` — via this change's delta.
- Consumers (identus-ws) — breaking: their shim's `require` field and
  require path update on upgrade; prior tag pins defer it.
