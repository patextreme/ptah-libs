## Why

The Factory Components library (the shared Luau workflow library: stdlib
helpers + workflow components) lives in the ptah repository, distributed only
as a manually mounted source tree — no versioning, no pinning, no upgrade
path. ptah is adopting pesde as its dependency manager, so the library needs
its own home from which consumers can take it as a versioned git dependency.
This repository becomes that home.

## What Changes

- Copy `factory-components/` (stdlib: `session-config`, `predicate`, `gh`,
  `daemon`; components: `openspec`, `pr-review-loop`; plus READMEs) from the
  **ptah `main` snapshot at `6307bd5`** into this repo, unchanged. Ongoing
  edits in ptah are ignored; that snapshot becomes the authoritative copy and
  ptah's copy is considered frozen.
- Add a package entry `lib.luau` (deliberately **not** `init.luau` — see
  design) exporting, in camelCase:
  `{ std = { predicate, gh, daemon, sessionConfig }, openspec, prReviewLoop }`.
- Add `pesde.toml`: name `patextreme/ptah_libs`, version `0.1.0`
  (placeholder — no release yet), target `luau`, `lib = "lib.luau"`,
  `includes` covering the tree, entry, and docs. The package is consumed as a
  **pesde git dependency (tag-pinned)**; it is never published to a registry
  and this repo commits no lockfile.
- Add README (git-dependency consumption model, shim example, versioning
  policy, per-release minimum-ptah statement), MIT LICENSE, and `.gitignore`
  (ignore `.pesde/`).
- Create `CONTEXT.md` here: the library terms move from ptah's glossary
  (Factory Components, stdlib, Component, Shim, Local config, Session
  config, Convergence loop, Task scope, Reviewer instruction); the
  "Mount point" term is dropped; ptah's own glossary edit is deferred to
  ptah's future adoption change (out of scope here).
- Create the `factory-components` capability spec in this repo: the behavior
  requirements move from ptah's spec, reframed from source-mount consumption
  to pesde git-dependency consumption; ptah's copy stays untouched until its
  adoption change.

Explicitly out of scope (deferred, untracked in ptah for now): ptah's
adoption (shims, tests, nix, README/skill rewrites, tree deletion), tagging
`v0.1.0`, any test suite/CI in this repo, and publishing.

## Capabilities

### New Capabilities

- `factory-components`: the shared workflow library's behavior contract —
  session-config application, typed judge, GitHub CLI transport, daemon loop
  skeleton, component facade contract, the openspec and pr-review-loop
  components, library self-containment, offline coverage, and the new
  package-consumption requirement (single pesde entry, named exports,
  git-dependency installability).

### Modified Capabilities

(none — this repo has no existing specs; ptah's spec copy is untouched.)

## Impact

- This repo only: new files (`factory-components/**`, `lib.luau`,
  `pesde.toml`, `README.md`, `LICENSE`, `.gitignore`, `CONTEXT.md`, spec
  delta). No existing code changes; the Luau modules are byte-identical
  copies.
- Consumers (ptah, later): switch from mounting the tree to a pesde git
  dependency `{ repo = "…/ptah-libs.git", rev = "vX.Y.Z" }` and require the
  generated `luau_packages/ptah_libs` shim instead of deep paths. Deep-path
  requires (`factory-components/components/…`) stop being the supported
  surface once adoption happens.
- Open risks, accepted for now and revisited at first tag: (1) the manifest +
  entry shape has never been installed by pesde (`pesde install` as a git
  dep); (2) whether `ptah check`'s luau-lsp pass resolves the generated
  `luau_packages/<alias>.luau` shim into `.pesde/…`; (3) the known
  luau-lsp quirk that init-named entry modules resolve internal requires one
  directory off — mitigated by the `lib.luau` entry name.
