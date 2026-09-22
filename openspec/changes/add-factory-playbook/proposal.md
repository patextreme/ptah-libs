# Proposal

## Why

Three consumer repositories (ptah-libs itself, lace-id-portal,
midnight-verifiable-credential-digital-passport) carry line-for-line
identical ~300-line factory shims — claim the oldest eligible issue →
provision its worktree → apply the mapped openspec change or edit
directly → open the issue-linked PR → run the convergent PR review loop —
that drift only in Local config values and repo-specific prompt text.
The label vocabulary has already drifted (`ai-r4d` exists in three
colors, with a description on only one repo), and a fresh consumer has no
bootstrap for either. The stable skeleton belongs in the library, where a
tag bump converges all consumers instead of a copy-paste patch.

## What Changes

- Add the **factory composition playbook** (`playbooks/factory/`): it
  composes the issue, openspec, and pr playbooks and **constructs those
  instances internally** from its own data-only config (ADR 0006). Verbs:
  `issueToPR(number?)` — one issue end-to-end, oldest eligible when no
  number is given — and `drain()` — loops it until the queue holds no
  eligible issue.
- Add module-level **`factory.initLabels(vocabulary?)`**: agent-free,
  idempotent label alignment — create the missing, update the drifted,
  never delete the unlisted, no renames in v1. A built-in canonical
  default vocabulary (`ai-r4d` / `0e8a16` /
  "Ready for the automated factory queue"); a configured vocabulary
  **replaces** the default wholesale, never merges.
- **Data-only config surface**: `agent`/`judgeAgent`/`reporterAgent` with
  their session configs, `queueLabel` (required, no default),
  `claimedLabel?`, `base` (required, no default; worktree ref derived as
  `origin/<base>`, PR base = `base`), `conventions` and `prContract`
  free-text prompt fragments injected into library-owned prompt
  skeletons, `maxReviewIterations` (default 10),
  `resolveChangeAttempts` (default 3), `openPullRequestAttempts`
  (default 3). Branch name is the fixed `issue-<n>`. openspec is
  mandatory in v1 (resolve → groom/implement/verify, else direct edit).
- **Outcomes as data** (`pr-reviewed` / `pr-non-converged` /
  `no-eligible-issue` / `failed`) with documented laws, not config:
  `drain`'s per-issue error boundary (log, continue, claim marker stays
  as audit trail), teardown on the success path only, and
  `pr-non-converged` recorded as a completed hand-off to a human, not a
  failure.
- The export surface gains `factory` (`lib.luau`, README exports table,
  consuming example).
- **Dogfood**: ptah-libs' own `.ptah/workflows/factory/main.luau` shrinks
  from the ~330-line logic shim to a config-only shim — the release gate.
- Explicitly out of v1: a `dryRun` pass-through (semantically broken for
  the composition — the committer opens the PR before the review loop
  needs to push fixes) and a `reviewPr` verb (a different entity;
  midnight's pr-review shim stays independent).

## Capabilities

### New Capabilities

(none — the project keeps one capability spec for the library; the
factory lands as new requirements in it, following the per-playbook
requirement pattern already used for the openspec, pr, and issue
playbooks.)

### Modified Capabilities

- `playbooks`: **Package consumption**'s export surface gains `factory`
  (entry exports `factory.new` and `factory.initLabels`). New
  requirements cover the factory playbook: internal sub-playbook
  construction, the data-only config surface with `base` unification and
  prompt fragments, `issueToPR`'s end-to-end semantics and outcome data,
  `drain`'s loop laws, and idempotent label alignment.

## Impact

- **Library**: `lib.luau` gains the `factory` export; new tree
  `playbooks/factory/` (playbook module, data module for the default
  label vocabulary, README). `README.md` exports table and consuming
  example updated. No existing playbook's behavior changes; no breaking
  changes (0.x minor bump carries the new surface).
- **Consumers**: lace-id-portal and
  midnight-verifiable-credential-digital-passport swap their factory
  shims for config-only ones as mechanical follow-ups pinned to the tag
  (out of this change's scope). Shim paths and the `factory:` log prefix
  are preserved.
- **Verification**: end-to-end runs against
  `patextreme/ptah-issue-sandbox` (no openspec tree → exercises the
  direct-edit path, label alignment including replace semantics, existing
  claim/pagination fixture culture; throwaway PRs) and the dogfood run on
  ptah-libs itself (exercises the openspec path) as the release gate.
- **Docs already in place from exploration**: `CONTEXT.md` glossary
  (Factory (playbook), Label vocabulary, Prompt fragment; Playbook
  definition extended with compositions) and
  `docs/adr/0006-factory-composition-playbook.md`.
