# Tasks

## 1. Playbook module

- [ ] 1.1 Create `playbooks/factory/playbook.luau` (`--!strict`): export
  `Config` (agent/judgeAgent/reporterAgent, three session-config arrays,
  `queueLabel`, `claimedLabel?`, `base`, `conventions?`, `prContract?`,
  `maxReviewIterations?`, `resolveChangeAttempts?`,
  `openPullRequestAttempts?`), raise at `new()` on missing `queueLabel`
  or `base` naming the field. Verify: `ptah check` passes on a shim
  config omitting each required field and naming it in the error.
- [ ] 1.2 Implement `issueToPR(number?) -> Outcome`: claim via the issue
  playbook (scan or explicit number), provision the worktree
  (`issue-<n>` off `origin/<base>`, fetch, adopt/resume semantics),
  resolve the change (typed hand-off bounded by
  `resolveChangeAttempts`), drive groom → implement → verify or direct
  edit with the `conventions` fragment, open the PR via the delivery
  prompt skeleton (D5 mechanics + `prContract` fragment, typed hand-off
  bounded by `openPullRequestAttempts`, body carries `Closes #<n>`),
  run the pr playbook review with `maxReviewIterations`, map the review
  status to `pr-reviewed`/`pr-non-converged`, tear down on the success
  path only. Session ids `factory-resolve:<n>`/`factory-direct:<n>`/
  `factory-pr:<n>`, log prefix `factory:`. Verify: `ptah check` passes;
  module requires resolve through the root `.luaurc` alias.
- [ ] 1.3 Implement `drain() -> { Outcome }`: loop `issueToPR()` behind a
  per-issue `pcall` boundary (log `factory: issue #N failed: …`, keep
  worktree and claim), stop on `no-eligible-issue` reporting the scanned
  count. Verify: code review against the spec's drain scenarios; no
  configuration surface for the boundary or stop condition.
- [ ] 1.4 Implement the label-alignment module function
  `initLabels(vocabulary?)` over `std/gh`: read labels, create missing,
  edit drifted color/description, never delete, no renames; default
  vocabulary from the data module; configured vocabulary replaces
  wholesale. Verify: twice-in-a-row run against
  `patextreme/ptah-issue-sandbox` performs writes on the first and none
  on the second (`gh api repos:…/labels` before/after diff is empty).
- [ ] 1.5 Create the data-only sibling module with the canonical default
  vocabulary (`ai-r4d` / `0e8a16` / "Ready for the automated factory
  queue") following the `pr/default-instruction.luau` pattern. Verify:
  `ptah check` passes; `initLabels()` with no argument uses it.

## 2. Export and library docs

- [ ] 2.1 Export `factory` from `lib.luau`. Verify: `ptah check` passes
  and the README exports-table row is added for `factory` (composition
  playbook: `issueToPR`, `drain`, `initLabels`).
- [ ] 2.2 Update `README.md`: consuming example shows a config-only
  factory shim (`factory.new({ queueLabel = …, base = …, conventions =
  …, prContract = … }):drain()`), exports table row, and the playbook
  contract note that config carries no playbook instances. Verify:
  example matches the actual `Config` type (names, optionality).
- [ ] 2.3 Create `playbooks/factory/README.md` declaring environment
  requirements (`pi` agent resolving in the registry, `gh`
  authenticated, `git`, `openspec` on PATH), the label-vocabulary
  contract, the outcome taxonomy, and the laws (error boundary,
  teardown-on-success, non-converged-as-hand-off). Verify: delivered
  artifact matches design D7/D8 wording.

## 3. Verification

- [ ] 3.1 Sandbox end-to-end (direct-edit path): run a `factory.new`
  config shim against `patextreme/ptah-issue-sandbox` (its own
  `queue`/`claimed` vocabulary via `initLabels`, then `issueToPR()` on a
  prepared fixture issue). Verify: claim marker + assignee on the
  fixture, worktree under `.ptah/worktree/`, PR opened against the
  sandbox default branch with `Closes #<n>`, review loop reports,
  `pr-reviewed` or `pr-non-converged` outcome returned, worktree torn
  down.
- [ ] 3.2 Sandbox failure path: point a run at a fixture whose delivery
  cannot succeed (e.g. `openPullRequestAttempts` exhausted by an
  unresolvable base). Verify: `failed` outcome with the error, worktree
  kept, claim marker intact, and a following `drain()` continues past
  it.
- [ ] 3.3 Label alignment on the sandbox: `initLabels()` default
  (creates `ai-r4d` canonically), then the sandbox's own two-label
  vocabulary (no merge), then drift one color and re-align. Verify:
  each scenario's observable end state matches the spec's label
  alignment scenarios.
- [ ] 3.4 Dogfood release gate: swap ptah-libs'
  `.ptah/workflows/factory/main.luau` to the config-only shim (root
  `.luaurc` alias require), run one real issue end-to-end through the
  openspec path (resolve → groom → implement → verify → PR → review).
  Verify: the shim is config only, the run completes with a
  `pr-reviewed`/`pr-non-converged` outcome, and the change's specs/tasks
  artifacts were not touched by the run.

## 4. Release prep

- [ ] 4.1 Confirm no new ptah script surface is bound (no minimum-ptah
  row needed) and bump the package version as a 0.x minor in
  `pesde.toml`. Verify: `pesde install` in a scratch consumer with the
  new tag resolves and exposes `factory`.
- [ ] 4.2 Post-merge note for consumers: lace-id-portal and midnight
  swap their shims pinned to the tag (paths and log prefix preserved) —
  a follow-up outside this change. Verify: note delivered in the change
  archive summary.
