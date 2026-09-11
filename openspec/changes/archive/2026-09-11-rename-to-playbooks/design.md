## Context

See `proposal.md` — Why. The constraints that shape the approach:

- The library tree is a frozen, byte-identical copy from ptah's `main` at
  `6307bd5` (archived `move-factory-components` change); ptah's own copy stays
  frozen, so this repo is free to move its own tree.
- ptah's require resolver and luau-lsp agree on a module's internal relative
  requires only when the module is **not** named `init.luau` — the reason
  component facades are `component.luau` today, and the reason any
  replacement name must stay non-`init`.
- pesde package shape: one `lib` entry (`lib.luau`) re-exporting a named
  camelCase surface; consumers reach the library through the generated
  `luau_packages/ptah_libs` shim. Internal tree paths are invisible to
  consumers.
- OpenSpec has no capability-rename operation: capability identity is the spec
  directory plus the `# <name> Specification` title, and delta operations are
  requirement-level only (`ADDED`/`MODIFIED`/`REMOVED`/`RENAMED`).
- `.luaurc` holds a **user-owned** alias (ptah's package sync never rewrites an
  alias whose target is outside `.ptah/luau_packages/`), which is how in-repo
  `.ptah/workflows/…` shims require the live tree during development.

## Goals / Non-Goals

**Goals:**

- One vocabulary across tree, glossary, docs, and the spec capability:
  **Ptah Playbooks**.
- The tree moves with **no edits to module code** beyond the facade file names.
- The supported consumer surface is unchanged.

**Non-Goals:**

- Renaming the repo (`ptah-libs`), the pesde package (`patextreme/ptah_libs`),
  or the alias (`ptah_libs`).
- Cutting a tag or bumping the placeholder version.
- Touching ptah's frozen copy or `openspec/changes/archive/**`.
- Changing requirement *behavior* — only the unit vocabulary changes.

## Decisions

**Flatten to `std/` + `playbooks/`, not a `playbooks/` container.**
`factory-components/components/X/…` and `playbooks/X/…` are both exactly two
levels below the package root, so the components' `../../std/…` requires keep
resolving with no edits — the tree stays the frozen copy, merely relocated. A
container (`playbooks/std/…`) would force `../../std` → `../std` in six places
and read oddly (`playbooks/std`). The flattened shape also mirrors the export
surface (`{ std, …playbooks }`). Alternative — container — rejected for the
extra edits and the odd nesting.

**Brand ≠ identity: keep `ptah-libs` / `patextreme/ptah_libs` / `ptah_libs`.**
"Playbooks" is the library's brand; `ptah_libs` is its identity, and identity
is what consumers pin in a pesde dependency spec. Renaming the repo would
break the remote URL, the open PR, and every consumer's `repo = …/ptah-libs.git`
spec for no gain. Alternative — rename everything — rejected.

**Facade `component.luau` → `playbook.luau`.**
Retiring "Component" from the glossary while leaving `component.luau` in every
path recreates the drift this change removes. `playbook.luau` is equally
non-`init`, so the luau-lsp quirk mitigation holds. Touches the two facades,
`lib.luau`'s requires, and the READMEs. Alternative — keep `component.luau` as
a generic "facade module" name — rejected as residual drift.

**In-repo alias retargeted to `./`.**
With the tree flattened, the alias base is the package root. Verified that a
`"./"` alias target resolves in both `ptah check` and `ptah run`. The alias is
in-repo development-only (never part of the consumer surface), so the widened
scope is acceptable; a boundary directory would reintroduce the nesting the
flatten rejects. Alternative — keep a container to scope the alias — rejected.

**Capability rename as retire + recreate.**
OpenSpec offers no capability rename, so the change carries two deltas: an
`ADDED` delta at `specs/playbooks/spec.md` (new capability: `## Purpose` + the
requirements with the unit vocabulary renamed) and a `REMOVED` delta at
`specs/factory-components/spec.md` (all requirements retired, each with Reason
and Migration), plus `retire_capabilities: true` in `.openspec.yaml` so the
archive flow deletes the old capability. Alternatives — a plain
`git mv` of the spec directory (not a delta operation; the archive flow would
have nothing to merge and could not express the rename) and keeping the
capability named `factory-components` (the drift the proposal rejects) — both
rejected.

**README consolidation.**
The 171-line library README and the root README overlap (both carry Layout and
Contracts sections), and flattening removes the container that would hold the
library README. Merge them into the root `README.md`; keep `std/README.md` and
`playbooks/README.md` (the former 22-line components README) as per-layer
detail. Alternative — keep the library README as `playbooks/README.md` —
rejected because it would place a `std/`-covering document under `playbooks/`.

**Archive untouched.**
`openspec/changes/archive/**` is the record of what happened; the move design
already treats openspec (not ADRs) as the decision record. One stale reference
in the library README to a non-existent `2026-09-04-factory-components` change
is corrected in passing.

## Risks / Trade-offs

- [Deep-path requires break] → Accepted: deep paths into the tree are
  explicitly not a supported consumer surface (`Package consumption`
  requirement); consumers use the generated shim. The in-repo shim is updated.
- [Retire+recreate duplicates all requirements in the delta] → Mitigated by
  generating the `ADDED` delta mechanically from the current main spec (a
  documented `Component`→`Playbook` substitution) rather than by hand, and by
  validating the change before archive.
- [The capability retirement needs `retire_capabilities: true` and a
  well-formed removal] → The change sets the marker and removes *every*
  requirement, satisfying the archive flow's retirement conditions; the
  removal delta names each requirement explicitly.
- [ptah still names the library "factory-components" in its frozen copy] →
  Expected and accepted: ptah's tree is frozen and this rename needs no
  cross-repo coordination; ptah's future adoption change updates its side.
- [A `./` alias exposes the whole repo root to `@ptah_libs/…`] → In-repo
  development only, `.luau`-only resolution; accepted.

## Migration Plan

1. Move the tree and rename the facades (history-preserving `git mv`).
2. Rewire `lib.luau`, `pesde.toml`, `.luaurc`, and the in-repo shim.
3. Consolidate docs and rename the glossary terms.
4. Sync the capability rename into `openspec/specs/` (archive the change).
5. Verify: `ptah check` on the shim, `openspec validate --specs`, and a Helix
   (luau-lsp) pass over an `@ptah_libs/…` require.

Rollback is a `git revert`; nothing outside this repo depends on the internal
layout, and no tag exists yet.

## Open Questions

(none)
