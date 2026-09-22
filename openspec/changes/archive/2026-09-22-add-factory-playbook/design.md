# Design

## Context

Three factory shims (ptah-libs, lace-id-portal,
midnight-verifiable-credential-digital-passport) are line-for-line
identical except for Local config values and repo prompt text — the
skeleton is stable and library-shaped. The library contract already
provides every piece the skeleton composes: issue pickup (claim
protocol), openspec playbook (groom/implement/verify), pr playbook
(convergent review), std worktree (provision/teardown), std gh
(transport), session config. See proposal.md — Why. During exploration
the glossary and ADR 0006 were written
(`CONTEXT.md`, `docs/adr/0006-factory-composition-playbook.md`); this
design implements them.

## Goals / Non-Goals

**Goals:**

- One library-owned factory playbook; consumer shims shrink to config.
- The three live shims' accumulated lessons (push-upstream mechanics,
  `Closes #<n>`, hand-off retry bounds, teardown policy) become library
  law, not per-repo rediscovery.
- Label vocabulary bootstrap and drift repair via an idempotent,
  agent-free alignment function.
- Verification that exercises both implementation paths (direct edit on
  the sandbox, openspec lifecycle on the dogfood run).

**Non-Goals:**

- No `dryRun` pass-through (semantically broken for the composition: the
  committer opens the PR before the review loop needs to push).
- No `reviewPr` verb (a different entity; midnight's pr-review shim
  stays independent).
- No openspec-less mode, no label renames, no consumer migrations inside
  this change (they pin to the tag afterwards).
- No change to the composed playbooks' own behavior or specs.

## Decisions

**D1 — Composition playbook, real export (not a recipe).** The value is
"shim shrinks to config and tag bumps converge consumers"; a documented
template converges nothing. ADR 0006 records the trade-off and the
rejected recipe/new-unit-kind alternatives.

**D2 — Sub-playbooks constructed internally.** `factory.new(config)`
builds its issue/openspec/pr instances; config accepts no playbook
instances. Rejected injection: it re-exposes three config surfaces onto
every shim and breaks "config is data" (a playbook instance is neither
data nor a ptah runtime handle). Consequence: the factory's config
flattens the composed playbooks' knobs (agent handles, session configs
per role, `queueLabel`/`claimedLabel`, `maxReviewIterations`) plus its
own (`base`, fragments, attempt bounds).

**D3 — One `base` field.** In all three shims the worktree ref and PR
base are the same branch and have never split; the factory takes
`base = "develop"` (required, no default — the delivery base is the
repository's, like the queue label) and derives the worktree ref as
`origin/<base>`. Rejected: two knobs (`worktreeRef`, `prBase`) for a
split nobody has ever wanted.

**D4 — Repo knowledge as two free-text prompt fragments.** `conventions`
(direct-edit prompt: docs to read, test commands) and `prContract`
(delivery prompt: signing, commit format, PR title/body contracts).
Free text because the content is prose law (midnight's committer
contract is ~30 lines of repo-specific rules); structured flags would
torture that into a schema, and fragments keep the skeletons
library-owned. Fragments may instruct the agent to read the repo's CI
contract (midnight's pr-check.yml pattern) instead of restating it —
restatement drifts. Attempt-bound field names mirror their steps:
`resolveChangeAttempts` (default 3), `openPullRequestAttempts`
(default 3).

**D5 — Push mechanics are skeleton law; contracts are fragment content.**
The delivery prompt's skeleton encodes the correctness lessons all runs
need: commit on the pre-created `issue-<n>`, push with
`-u --force-with-lease` (the lease is safe on resumed runs; `-u`
repoints the upstream the branch inherited from `origin/<base>` so the
review loop's later bare `git push` lands on the PR branch), and
`Closes #<n>` in the body (the issue's release protocol). Signing, CC
formats, lint allowlists are repo law → `prContract`. Default skeleton
matches the ptah-libs shim: plain Conventional Commits, `gh pr create
--base <base>`.

**D6 — Branch fixed `issue-<n>`; naming callback rejected.** Three
repos, zero variance; a `fn(issue) -> branch` config amends the
data-only contract for no demonstrated need (ADR 0006). A template
string remains the escape hatch if variance ever appears.

**D7 — Verbs and surfaces.** `issueToPR(number?) -> Outcome` (the issue
playbook's `pickUp` already supports explicit-number pickup, so
single-issue mode is nearly free and is the human steering tool);
`drain() -> { Outcome }` loops it; `factory.initLabels(vocabulary?)` is
a module-level function (label bootstrap needs no agent handles; same
playbook module per the entity coupling) with **replace** semantics and
the built-in canonical default (`ai-r4d` / `0e8a16` / "Ready for the
automated factory queue" — the library home repo's values; the sandbox's
`queue`/`claimed` two-label vocabulary is the replace-semantics
scenario). Alignment is `gh label` create/edit over the declared list:
create missing, update drifted, never delete, no renames.

**D8 — Outcomes as data; policies as law.** `pr-reviewed` /
`pr-non-converged` / `no-eligible-issue` / `failed`, mirroring the
library's outcomes-as-data convention. The drain's per-issue error
boundary (log, continue, claim stays), teardown-on-success-only, and
non-converged-as-hand-off are documented laws, not config — all three
shims agree on them and none should be able to drift. Session ids keep
the shim shapes (`factory-resolve:<n>`, `factory-direct:<n>`,
`factory-pr:<n>`); log lines keep the `factory:` prefix for grep
compatibility.

**D9 — openspec mandatory in v1.** All known consumers use it and the
resolve step already degrades to direct edit; a `directEditOnly` flag
would ship untested config space. Revisit on the first openspec-less
consumer.

**D10 — Module layout follows the house pattern.**
`playbooks/factory/playbook.luau` (facade, `new(config)`), a data-only
sibling module for the default label vocabulary (the
`pr/default-instruction.luau` pattern), and a README declaring the
environment requirements (`pi` agent, `gh` authenticated, `git`,
`openspec`). The playbook requires its siblings
(`../issue/playbook`, `../openspec/playbook`, `../pr/playbook`) and
`std/` modules by relative path, inside the self-containment contract.
Per-issue instances: the openspec and pr playbooks are constructed per
worktree around its path (as all three shims do today); the issue
playbook instance is constructed once per factory instance.

## Risks / Trade-offs

- [No offline test suite (pending upstream ptah); verification is live
  agent runs] → Three-legged plan: sandbox end-to-end (direct-edit path,
  label alignment incl. replace semantics, claim fixtures; throwaway
  PRs), dogfood run on ptah-libs (openspec path) as the release gate,
  and `ptah check` as the type-level gate on the new config surface.
- [Live runs open real PRs and real labels on the sandbox] → Accepted:
  the sandbox is declared throwaway and already carries hundreds of
  fixture issues; no fixture-building work in v1.
- [Large flattened config surface invites misconfiguration] → Required
  fields raise at construction with named fields; README example is the
  copy source; `ptah check` validates shim configs against the exported
  config type on tag bump.
- [Fragment restatement drift vs repo CI contracts] → D4's
  read-the-workflow pattern; the library skeleton never restates a
  repo's lint rules.
- [Bounded hand-offs fail an issue an agent would have finished] →
  Designed degradation, as in all three shims: the failure keeps the
  worktree and claim as audit trail and `drain` moves on.

## Migration Plan

1. Implement the playbook tree, export, and docs (tasks below).
2. Swap ptah-libs' own `.ptah/workflows/factory/main.luau` to the
   config-only shim (root `.luaurc` alias require) — the dogfood run is
   the release gate.
3. Cut the 0.x minor tag; add the minimum-ptah row if the surface binds
   to new ptah script APIs (it does not — no new ptah surface is used).
4. Consumers (lace-id-portal, midnight) swap their shims pinned to the
   tag, in their own time; shims keep the
   `.ptah/workflows/factory/main.luau` path and `factory:` log prefix.
   Rollback at any consumer: pin the prior tag.

## Open Questions

None — the grilling session emptied the design tree; every branch above
carries a settled decision.
