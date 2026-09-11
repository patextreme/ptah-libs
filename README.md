# ptah-libs

[Factory Components](./factory-components/README.md) — the shared Luau
workflow library for [ptah](https://github.com/patextreme/ptah): repo-agnostic
stdlib helpers and composable workflow components that consumer repositories
drive through thin shims. This repository is the library's home; it is
consumed as a **pesde git dependency pinned to a tag** — never published to a
registry.

## Consuming

Declare a git dependency on this repository at a tag and install:

```toml
# pesde.toml (consumer)
[dependencies]
ptah_libs = { repo = "https://github.com/patextreme/ptah-libs.git", rev = "v0.1.0" }
```

`pesde install` generates a `luau_packages/ptah_libs.luau` shim in your repo
that requires the package entry and re-exports its values and types. Your
workflow code requires that generated shim — not any deep path into the
library tree (deep-path requires are not a supported surface):

```lua
--!strict
local libs = require("./luau_packages/ptah_libs")

local ops = libs.openspec.new({
	agent = ptah.agent("claude"),
	judgeAgent = ptah.agent("claude"),
	sessionConfig = { { id = "model", value = "claude-opus-4-5" } },
	judgeSessionConfig = { { id = "model", value = "claude-haiku-4-5" } },
})

ops:groom("add-auth")

-- also available:
-- libs.prReviewLoop.new({ ... })
-- libs.std.predicate.new({ ... })
-- libs.std.gh.run({ ... })
-- libs.std.daemon.run({ ... })
-- libs.std.sessionConfig.apply(session, entries)
```

## Exports

`lib.luau` returns the library's named camelCase surface, key-for-key:

| Key | Value |
| --- | --- |
| `std.predicate` | typed boolean judge (bounded retry; exhaustion is a script error) |
| `std.gh` | GitHub CLI transport over `ptah.exec` with structured outcomes |
| `std.daemon` | repo loop skeleton with per-repo error isolation |
| `std.sessionConfig` | ordered session-config entries — the shared apply mechanism |
| `openspec` | openspec change component (groom, implement, verify) |
| `prReviewLoop` | PR review→fix→push convergence component |

Components are constructed with `new(config)`; per-call data (a change name,
a PR URL) is a method argument. See the library README for the component
contract, loop conventions, and session-config semantics.

## Versioning

- **A tag is a release.** Cut `vX.Y.Z` when you want a consumable revision;
  everything between tags is work-in-progress.
- **During 0.x, breaking changes ship on minor bumps** (`0.1.0` → `0.2.0`
  may remove or reshape exports; patch bumps are fixes only).
- **Minimum ptah per release.** Each release states the minimum ptah
  version it requires, since the library binds to ptah's script surface
  (`ptah.agent`, `ptah.parallel`, `ptah.exec`, `session:setConfig`,
  `configOptions`):

  | ptah_libs | Minimum ptah |
  | --- | --- |
  | 0.1.0 | unreleased ptah main at snapshot `6307bd5` (session-config support; no ptah release published yet) |

- **Offline test coverage lives upstream — and is pending.** The library's
  offline suite (mock agent, no network, no real agent) is maintained in the
  [ptah repository](https://github.com/patextreme/ptah); this repo ships no
  tests. At snapshot `6307bd5` ptah has no such suite yet — until it lands,
  the library's regression contract is unbacked, and no tag should be cut.

## Contracts

- **Self-containment** — library modules only require other modules inside
  the tree, never write files inside it, and never depend on a relative
  working directory; the tree works at any install path, including a
  read-only one.
- **Data-only config** — component config is data (plus ptah runtime handles
  where a component's config type declares them); functions are never
  configuration.
- **`ptah check` is the compatibility gate** — every module is `--!strict`,
  components export their `Config` types, and a consumer's `ptah check`
  validates their shim config against those types when they bump. A removed
  or reshaped field is reported there, not at runtime.
  - *Known interaction with pesde's generated shim:* pesde writes
    `luau_packages/ptah_libs.luau` without a `--!strict` directive, and
    ptah's check pass (as of snapshot `6307bd5`) lints the strict directive
    over the whole literal require graph with no excludes — so a consumer
    shim that goes through the generated shim sees exactly one finding,
    naming that shim file. Types still flow: the analyzer resolves the
    generated shim into the pesde store and validates config against the
    library's exported types (verified by a real `pesde install` of this
    package). The exemption fix belongs to ptah's check pass; until a ptah
    release carries it, treat that single finding as the known shim one.

## Layout

- `lib.luau` — package entry (deliberately not `init.luau`; see the
  library README's note on the luau-lsp quirk).
- `factory-components/` — the library tree (byte-identical snapshot from
  ptah); see [factory-components/README.md](./factory-components/README.md).
- `pesde.toml` — package manifest (`luau` target, `lib = "lib.luau"`).
- `CONTEXT.md` — the library's vocabulary.