## Context

See `proposal.md` — Why. Constraints that shape the approach:

- **The library's extension model is fixed by contract**: config is data (no
  callable hooks), and extension happens through new playbooks and
  composition. `openspec/specs/playbooks/spec.md` already requires playbook
  facades, self-containment, and no agent construction.
- **The ptah pre-flight lints constrain library code**: a literal
  `ptah.agent("name")` is resolved against the *consumer's* registry over the
  literal require graph, and a literal `ptah.ask(` fails where no provider is
  configured. `std/escalate` already documents the aliasing workaround. This
  is why the playbook must take agent handles as config.
- **Playbooks accept no `cwd`** (by design — the self-containment rule forbids
  relative-working-directory dependence), so a per-issue worktree must be
  imposed by the caller. lace works around this with an ad-hoc agent proxy.
- **Facts found during research**: `ai-r4d` is local to
  `lace-id-portal`'s `issue-worker` branch (only that repo uses the label);
  `input-output-hk/identus-workspace` hand-rolls a `ci.luau` and a
  `merge-bot-prs` workflow but does not consume the library; the ptah
  mock-agent suite now exists (`crates/ptah-cli/tests/ptah_libs.rs`), though
  the ptah-libs README still claims it does not.

## Goals / Non-Goals

**Goals:**

- One reusable issue→PR lifecycle with repo specifics as data.
- A composition seam that is open for extension without callable hooks.
- Remove the duplication lace carries (shell helpers, cwd proxy, worktree
  mechanics) and the CI duplication in identus's lineage.
- Keep every consumer-owned line to a thin shim.

**Non-Goals:**

- Migrating `input-output-hk/lace-id-portal` to a shim. That landing is a
  **separate change gated on this library change merging to `main`**; this
  change does not touch lace (see D8 and the Migration Plan).
- Upstream offline coverage for the new playbooks and correcting the stale
  README note — the fix ships as a **follow-up OpenSpec change created before
  this change is archived**; no tag is cut by this change (see Risks).
- A daemon/loop operation (`std.daemon` already lets a consumer loop).
- Lifting git-worktree mechanics to `std` now (one consumer; see Decisions).
- Generalizing the review loop or openspec playbook — they already exist.

## Decisions

### D1 — Decomposition: one meta playbook plus a CI playbook and two std helpers

Ship `issueWorker` (the lifecycle), `ciGate` (check watching + repair),
`std.agent` (directory scoping), and `std.shell` (exec helpers). Keep git
mechanics private to `playbooks/issue-worker/git.luau`.

- *Alternative — one monolith*: rejected because `ciGate` has two
  independent reasons to exist: the pr-review-loop spec explicitly places CI
  outside that playbook, and identus's lineage already duplicates it.
- *Alternative — full split* (`pullRequestDelivery`, `issueQueue`): rejected
  as premature. `identus`'s `merge-bot-prs` merges, it does not produce a PR,
  so it is not the second consumer that would justify a delivery playbook.
  Splitting now multiplies untested surface for no demonstrated consumer.
- *Alternative — lift `std/git` now*: rejected against the library's own bar
  ("only mechanisms a third consumer would use verbatim"). git worktrees have
  one consumer today; promote when a second playbook needs them.

### D2 — Generalization posture: mechanics closed, prompts data-with-defaults

Deterministic mechanics are the library's (one implementation, no hooks):
worktree/branch invariants, delivery re-checks, label lifecycle, CI watch,
and the nested convergence loops. Agent-facing prompts are playbook-owned with
a configurable `repoBrief` injected, plus structured knobs for what varies
(`gateCommands`, `commitSignArgs`).

- *Alternative — parity port*: prompts keep lace's exact repo literals, which
  is not reusable and does not meet the "compose rather than fork" goal.
- *Alternative — per-stage prompt replacement*: a larger config surface for a
  need no consumer has yet; `repoBrief` covers the prose, and structured data
  covers the rest. It remains an additive escape hatch later.

### D3 — Naming: `issueWorker`, neutral, with a "Meta playbook" glossary term

The playbook is `issueWorker`; `readyLabel` is required and carries
`ai-r4d` in lace's shim. `CONTEXT.md` gains **Meta playbook** for a playbook
that composes std, other playbooks, and deterministic stages.

- *Alternative — `processR4dIssue`*: rejected. `ai-r4d` is one repo's private
  label; a shared unit named after it would be misleading for every other
  consumer. lace's consumer-owned shim may take the label-flavored name.
- *Alternative — "Lifecycle playbook"*: rejected because `CONTEXT.md` already
  uses "lifecycle" for a leaf playbook ("an openspec lifecycle").

### D4 — Directory scoping: `std.agent.inDirectory` with force-cwd, wrapped once

`issueWorker` wraps the configured `agent` handle once per issue and uses the
wrapped handle for every session — its own stages and the nested playbooks.
No stage sets `cwd` itself. The wrapper force-overwrites `cwd`.

- *Alternative — default-only or conflict-error*: rejected; the helper's
  purpose is to pin, playbooks pass no `cwd`, and an error mode adds no value.
- *Alternative — add `cwd` to playbook config*: rejected; it contradicts the
  self-containment rule and would change two shipped playbooks.

### D5 — Outcome and failure contract: typed outcomes, bookkeeping in the playbook

`run` / `process` return a discriminated outcome (`delivered` / `rejected` /
`idle` / `failed`); the playbook records a stage failure (comment, label swap,
release claim) and returns `failed`; the shim maps outcomes to exit codes. Two
nested outcomes fail the run, mirroring each other: a CI gate `unresolved`, and
a PR review loop that returns non-converged. Both are recorded through the same
failure bookkeeping and return a `failed` outcome carrying the reason — the
review verdict for the latter — so a pull request with open blocking findings is
never reported `delivered`. The playbook never calls `ptah.exit` or
`ptah.ask`; nested playbooks escalate through their own mechanism.

- *Alternative — raise and let the shim catch*: rejected; it splits the
  bookkeeping across the boundary and matches neither `prReviewLoop`'s
  outcomes-as-data convention nor the "one place for the paper trail" rule.

### D6 — Config surface: required repo shape, defaulted caps, dropped cosmetics

Required: `readyLabel`, `blockedLabel`, `baseBranch`, `branchPrefix`,
`gateCommands`. Defaulted: `worktreeDir` (default `"tmp"` relative to the
repository root, resolved to an absolute path before use so no exec runs with
a relative working directory), `pickupLimit` (bounds the candidate issues
inspected while searching; a run still claims and processes at most one),
`maxAttempts` (bounds the playbook's own typed-result retries — the triage
verdict and the delivery session's pull-request URL), `reviewMaxIterations`
(forwarded to the nested PR review loop's cap), `commitTypes`
(the conventional-commit vocabulary the triage verdict draws from),
`commitSignArgs` (also forwarded to the nested CI gate for its repair commits),
`openspec`, and the CI bounds. Dropped as config: label colors (built-in
defaults). Role handles and the three session-config arrays follow the
existing playbooks: `agent` / `sessionConfig` drive the playbook's own stages
and are forwarded as the work role to every nested playbook,
`judgeAgent` / `judgeSessionConfig` reach the nested openspec and
pr-review-loop judges, and `reporterAgent` / `reporterSessionConfig` reach the
nested PR review loop.

- *Alternative — default the labels*: rejected; it would bake `ai-r4d` into
  the library, which D3 rejects.

### D7 — openspec route is opt-in

When the flag is off, triage offers only `direct` and `reject`, and the run
requires no openspec CLI or skills. When on, the openspec route drives the
existing openspec playbook (groom → implement → verify) and requires the named
change directory to exist first.

- *Alternative — always on*: rejected; it would force the openspec
  environment on consumers that do not use openspec.

### D8 — Lace migration deferred to a separate landing, pinned to `rev = "main"`

Lace's ten modules collapse to one shim that requires this package, but that
landing is **out of scope for this change**: it ships as a separate change
gated on this library change merging to `main`, so this change stays a
single-repo, self-verifiable unit and does not touch
`input-output-hk/lace-id-portal`. The dependency stays pinned
`rev = "main"` as the documented target for when the shim lands; `pesde.lock`
then records the resolved tree id, so `rev = "main"` is reproducible at lock
time, and the tag-pinned model in the *Package consumption* spec remains the
documented target.

- *Alternative — shim in the same change*: rejected by the user; the library
  must land on `main` first, and a cross-repo edit cannot be verified against
  a `main` that does not yet carry the new exports.
- *Alternative — pin a merge SHA or cut a tag*: rejected by the user; the lock
  (once the shim lands) already provides reproducibility, and this change
  deliberately cuts no tag.

### D9 — Module boundary: `std/shell` shared, no issue/PR domain in std

`std.gh` and `std.daemon` route their private `trim` / `quote` /
`errorMessage` through `std/shell`. GitHub *issue and pull-request* domain
logic stays in playbooks over `std.gh`; `std` stays transport-and-mechanism
only.

- *Alternative — leave the private copies*: rejected; three copies of POSIX
  quoting is exactly the drift the library exists to prevent.

## Risks / Trade-offs

- **The change adds the largest module in the tree with no offline coverage**
  → The permanent *Offline test coverage* requirement stays unsatisfied until
  the follow-up; the follow-up change is a hard deliverable of this change
  (created before archive), and no tag is cut. The deterministic
  re-checks (commits-ahead, URL shape, title, label lifecycle) stay in the
  playbook so the safety net is by construction.
- **The stale README claim ("no suite yet … no tag") is left standing** → The
  user chose to defer it; it is listed as a non-goal, and the follow-up change
  (created before archive) corrects it before any tag.
- **The lace landing is now out of scope** → This change touches only this
  repository and is verifiable on its own via `ptah check`; the lace shim is a
  separate landing gated on the library merging to `main` (see D8 and the
  Migration Plan).
- **Concurrent runs racing on the same issue** → The claim is the assignee
  write verified by a re-read: after assigning itself, a run re-reads the
  assignee set and, unless it is exactly the authenticated user, releases
  itself and skips the issue rather than failing the run.
- **CI rollup shape drift** (check-run `conclusion`/`status` vs status-context
  `state`) → `ciGate` classifies across all three fields, and pending entries
  never read as failures.
- **Worktree directory is not automatically ignored** → `worktreeDir` defaults
  to `"tmp"`, which is not gitignored by default; the playbook README states
  the consumer is responsible for gitignoring it (the deferred lace shim will
  pass `worktreeDir = "tmp"` explicitly when it lands).
- **`repoBrief` prose is inlined into every stage prompt** → Documented, with
  the pointer style (reference a repo document) recommended for long text.

## Migration Plan

1. Land the library change on `main`: `std.agent`, `std.shell`, `std.gh` /
   `std.daemon` re-route, `playbooks/issue-worker/`, `playbooks/ci-gate/`,
   `lib.luau` exports, `CONTEXT.md`.
2. **(Separate landing, out of scope here)** Replace lace's
   `.ptah/workflows/issue-worker/` (ten modules) with the shim on the
   `issue-worker` branch and re-lock pesde (`rev = "main"`), gated on step 1
   having merged to `main`.
3. **(Separate landing)** Run `ptah check` on the shim from lace (the
   compatibility gate) and one dry validation of the lifecycle.
4. Rollback: the library change is additive and can be reverted independently;
   the separate lace landing carries its own rollback (revert the shim to the
   previous modules — the branch is unmerged).

## Open Questions

- None blocking. The follow-up coverage change (upstream ptah tests + README
  correction) is a separate change by decision, not an open question.
