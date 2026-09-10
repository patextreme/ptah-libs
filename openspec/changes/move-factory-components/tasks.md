## 1. Copy the library

- [ ] 1.1 Obtain the snapshot: `git clone https://github.com/patextreme/ptah.git` to a scratch dir outside this repo, then `git -C <clone> checkout 6307bd5` (pinned commit — `main` may advance past it). Copy its entire `factory-components/` tree (std: `session-config`, `predicate`, `gh`, `daemon`; components: `openspec`, `pr-review-loop`; all READMEs and supporting files such as `pr-review-loop/default-instruction.luau`) into this repo root, and verify with `diff -r` against the snapshot that the copy is byte-identical (no renames, no require-path changes)

## 2. Package shape

- [ ] 2.1 Create `lib.luau` at the repo root: `--!strict`, requires `./factory-components/std/predicate`, `./std/gh`, `./std/daemon`, `./std/session-config`, `./components/openspec/component`, `./components/pr-review-loop/component`, and returns `{ std = { predicate, gh, daemon, sessionConfig }, openspec, prReviewLoop }` — key-for-key as the Package consumption requirement states
- [ ] 2.2 Create `pesde.toml`: `name = "patextreme/ptah_libs"`, `version = "0.1.0"`, `description`, `license = "MIT"`, `repository` URL, `includes = ["lib.luau", "factory-components/**", "README.md", "LICENSE", "pesde.toml"]`, `[target] environment = "luau"`, `lib = "lib.luau"`; no `[indices]`, no lockfile; verify the entry is named `lib.luau` (not `init.luau`) and every transitively required file matches an `includes` glob

## 3. Docs and repo hygiene

- [ ] 3.1 Create `README.md`: what the library is, the git-dependency consumption model (`{ repo = "https://github.com/patextreme/ptah-libs.git", rev = "vX.Y.Z" }`, consumer requires the generated `luau_packages/ptah_libs` shim), a complete shim example using the named exports, the versioning policy (tag = release; breaking changes on minor bumps during 0.x; per-release minimum-ptah statement), and the contract pointers (self-containment, data-only config, `ptah check` as the compatibility gate)
- [ ] 3.2 Create `LICENSE` (MIT, copyright 2026 Pat Losoponkul) and `.gitignore` (`.pesde/`); verify `git status` shows only intended untracked files
- [ ] 3.3 Create `CONTEXT.md` with the moved library terms (Factory Components, stdlib, Component, Shim, Local config, Session config, Convergence loop, Task scope, Reviewer instruction) plus a ptah-libs package term; "Mount point" is deliberately absent; keep it a glossary only — no implementation details

## 4. Local verification (no pesde, no network)

- [ ] 4.1 Write a scratch `--!strict` shim (temp file outside the library tree) that requires `./lib.luau`, constructs both components via `new` with valid configs, and references every export key; run `ptah check` on it with this repo's `.ptah/ptah.d.luau`; expect zero findings, confirming strict types flow through the entry and the non-`init.luau` entry naming holds under the analyzer; delete the scratch file afterwards
- [ ] 4.2 Run `openspec validate move-factory-components --strict` and fix any reported artifact issues; confirm `git status` shows the copied tree byte-identical (still no library-code edits)
