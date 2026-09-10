## Context

The library exists today only in the ptah repository at `main` snapshot
`6307bd5` (stdlib `session-config`, `predicate`, `gh`, `daemon`; components
`openspec`, `pr-review-loop`), distributed as a manually mounted source tree
(the archived `factory-components` change's decision: source mount, no
registry, no lockfile). This repository is an empty skeleton: openspec
config, `.ptah/` project defs, `.helix/` — no code, README, LICENSE, or
package manifest.

pesde facts that shape the design (verified against docs.pesde.dev and the
CLI source): git dependencies take `{ repo, rev }` where `rev` may be a
commit, tag, or branch; a `luau`-target package requires a single `lib`
entry; every file transitively required must be covered by `includes`;
pesde generates a `luau_packages/<alias>.luau` shim in the consumer that
requires the package's `lib` and re-exports its `export type` declarations.
pesde itself is not in nixpkgs.

A known luau-lsp quirk (recorded in the library's README): a module named
`init.luau` has its internal relative requires resolved one directory off
under luau-lsp — which is what `ptah check` runs — hence the library's
component modules are named `component.luau`.

## Goals / Non-Goals

**Goals:**

- One authoritative copy of the library in this repo, byte-identical to the
  ptah `main` snapshot at `6307bd5`, frozen as the source of ongoing work
- A valid pesde package shape consumable as a git dependency: one entry,
  named camelCase exports, complete `includes`
- The behavior contract (specs) and vocabulary (CONTEXT.md) living with the
  library
- The supersession of the archived source-mount distribution decision
  recorded here, in openspec (no ADR file — openspec is the decision
  record)

**Non-Goals:**

- ptah-side adoption (shims, tests, nix, README/skill rewrites, tree
  deletion) — future work in that repo, untracked here
- Tagging `v0.1.0`, publishing to any registry, CI, or any test suite in
  this repo
- Changing any library code — the move is a copy, not a refactor
- Type definitions package (`.ptah/ptah.d.luau` stays embedded in ptah)

## Decisions

**Snapshot source: ptah `main` at `6307bd5`, ongoing edits ignored.**
The copy is taken from the current `main` branch state; unmerged work in
ptah is not waited for or merged first. ptah's tree is frozen from this
point: every subsequent library change lands here, and ptah's dogfooding
runs against the frozen snapshot until its adoption change replaces it.
Alternative — re-point ptah's mount at this repo now (mini-adoption) —
rejected: it contradicts the scoped decision to leave ptah untouched.

**Distribution: pesde git dependency, tag-pinned; no registry, no publish.**
This supersedes the archived change's "source mount, no registry, no
lockfile" decision: the registry half survives (still no registry), the
lockfile half reverses (consumers get pinning and reproducible installs via
`pesde.lock` on their side). Why pesde at all: manual mounts gave no
versioning, no upgrade path, and drift across consumer repos; a git
dependency gives pin-by-tag plus pesde's generated require shims and type
re-exports without operating or committing to registry infrastructure.
Alternative — keep source mounts — rejected for exactly the drift ADR-style
rationale above; alternative — publish to the public pesde index — rejected:
registry ownership/immutability commitments are unnecessary for a
single-consumer private library.

**Entry file: `lib.luau` at the package root, not `init.luau`.**
The recorded luau-lsp quirk makes init-named entry modules resolve their
internal requires one directory off under `ptah check`'s analyzer; a
distinctly named root entry sidesteps it exactly as `component.luau` naming
does inside the tree. The entry requires the unchanged
`factory-components/` tree and returns
`{ std = { predicate, gh, daemon, sessionConfig }, openspec, prReviewLoop }`
— camelCase keys matching the library's own config-field vocabulary
(`sessionConfig`, `judgeSessionConfig`, `dryRun`). Alternative — mirror the
directory layout (`components.openspec`, `components.prReviewLoop`) —
rejected: consumers type these names constantly; flat named exports read
better and stable module paths stay an internal detail.

**Internal layout: untouched tree.** `factory-components/{std,components/}`
is copied as-is; no module moves, no internal require changes, per-module
READMEs travel with the code. The entry file is purely additive.

**Manifest:** `name = "patextreme/ptah_libs"` (scoped name is required by
pesde's manifest format even though nothing is ever published; the scope
never gets claimed on an index), `version = "0.1.0"` as a placeholder —
bumped when the first tag is cut — `luau` target, `lib = "lib.luau"`,
`includes` covering the tree, entry, README, LICENSE, and the manifest
itself. No `[indices]` (never published); no lockfile committed (a
dependency-free library has none).

**Specs: carried with distribution-model edits; dogfood requirement
dropped.** Behavior requirements move verbatim from ptah's spec except:
"Library self-containment" scenarios reframe mount-at-any-path as
installed-at-any-path (pesde's store location is just another install
path — the requirement's substance is unchanged); "Offline test coverage"
notes the suite lives in ptah; a new "Package consumption" requirement
states the single-entry/named-exports/git-dependency contract. The
"Dogfooded in this repository" requirement is not carried — it is about
ptah's own `.ptah/workflows/`, is currently satisfied by the frozen
snapshot, and its future (dogfooding through the dependency) belongs to
ptah's adoption change.

**CONTEXT.md: library terms move here; "Mount point" dies.** Factory
Components, stdlib, Component, Shim, Local config, Session config,
Convergence loop, Task scope, Reviewer instruction move; the ptah-libs
package itself becomes a term. ptah's CONTEXT.md keeps its CLI terms plus,
temporarily, duplicate library terms until its adoption change edits them —
accepted drift, bounded by adoption.

## Risks / Trade-offs

- [The manifest + entry shape has never been installed by a real `pesde
  install`] → Accepted for now (decision: skip the smoke check while the
  feature is under implementation); must be verified before the first tag.
- [`ptah check`'s luau-lsp pass resolving the consumer-side
  `luau_packages/<alias>.luau` shim into `.pesde/…` is unverified] → Same:
  revisit at first tag; the `lib.luau` naming mitigates the known quirk
  class.
- [Coexistence drift: two copies of the tree exist until ptah adopts] →
  ptah's copy is frozen by policy and ptah's own archived change remains
  the record of what it froze; all library work lands here only.
- [Future modules must keep the `component.luau`/non-`init.luau` naming
  discipline] → Recorded in the library README (travels with the code) and
  in this design.
- [pesde is not in nixpkgs] → Affects only future ptah-side adoption
  (vendoring via release binary or cargo build); noted here so it isn't
  rediscovered.

## Migration Plan

Greenfield for this repo — no migration. The eventual ptah-side migration
(declare the git dependency, rewrite shims to `require` the generated shim,
delete the frozen tree, move the offline tests' consumption model) happens
in a ptah change when ptah adopts; this design's snapshot and entry
decisions are what that change will build on. Rollback here is trivial:
delete the copied files; nothing else depends on them yet.

## Open Questions

(none)
