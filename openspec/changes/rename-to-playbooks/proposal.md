## Why

The library is called **Factory Components** — a generic "software factory"
metaphor that names a place rather than a thing, and says nothing about what
this repo actually is: a library of reusable **agent-workflow playbooks** for
ptah. The vocabulary has also drifted: the package identity is
`patextreme/ptah_libs` / `ptah_libs`, the tree is `factory-components/`, the
unit term is "Component", and the OpenSpec capability is `factory-components`
— four names for one thing. This change collapses them onto one coherent
vocabulary, **Ptah Playbooks**, and takes the opportunity (before the first
tag is cut) to flatten the tree so the internal layout matches the library's
shape.

## What Changes

- **Rename the vocabulary**: the library becomes **Ptah Playbooks**; the unit
  term **Component** becomes **Playbook**; **stdlib** is unchanged. The
  repo/package/alias identity (`ptah-libs`, `patextreme/ptah_libs`,
  `ptah_libs`) does **not** change.
- **Flatten the tree**: `factory-components/{std,components}/` becomes `std/`
  plus `playbooks/` at the package root. Relative-require depth is preserved,
  so the library modules move with no code edits.
- **Rename the facade module**: `playbooks/<name>/component.luau` becomes
  `playbooks/<name>/playbook.luau`.
- **Retarget the in-repo alias**: `.luaurc` maps `ptah_libs → ./` (was
  `./factory-components`).
- **Update the package wiring**: `lib.luau` requires `./std/…` and
  `./playbooks/…/playbook`; `pesde.toml`'s `includes` becomes `std/**` plus
  `playbooks/**`, and its description is rewritten.
- **Consolidate the docs**: merge the library README into the root `README.md`;
  update `std/README.md` and `playbooks/README.md`; rename the `CONTEXT.md`
  glossary terms, parking "Factory Components" and "Component" in `_Avoid_`.
- **Rename the OpenSpec capability**: `factory-components` → `playbooks`,
  expressed as a retire+recreate (all requirements move verbatim under the new
  capability; the old capability is retired).
- **Leave history alone**: `openspec/changes/archive/**` is untouched.

Not consumer-breaking: consumers reach the library through the generated
`luau_packages/ptah_libs` shim, and the package name, entry, alias, and export
surface are all unchanged. Only deep-path requires into the tree change — and
those are explicitly not a supported consumer surface.

## Capabilities

### New Capabilities

- `playbooks`: the shared workflow library's behavior contract — the
  requirements formerly carried by the `factory-components` capability,
  carried over under the library's new name with the unit vocabulary renamed
  (Component → Playbook).

### Modified Capabilities

- `factory-components`: retired — every requirement moves verbatim to
  `playbooks` and the capability is removed. OpenSpec has no capability-rename
  operation, so a rename is expressed as retire+recreate.

## Impact

- **Moved**: `factory-components/{std,components}/` → `std/` + `playbooks/`,
  with facade modules renamed `component.luau` → `playbook.luau`.
- **Edited**: `lib.luau`, `pesde.toml`, `.luaurc`, `README.md`, `CONTEXT.md`,
  `std/README.md`, `playbooks/README.md`, `openspec/specs/` (capability
  retire+recreate), and the gitignored in-repo shim
  `.ptah/workflows/adhoc/main.luau`.
- **Unchanged**: the pesde package name (`patextreme/ptah_libs`), the entry
  (`lib.luau`), the alias (`ptah_libs`), and the export surface (`std`,
  `openspec`, `prReviewLoop`).
- **Unaffected**: ptah's frozen copy of the tree
  (`crates/ptah-cli/tests/factory_components.rs`) — no cross-repo coordination.
