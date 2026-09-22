# Spec Delta

## MODIFIED Requirements

### Requirement: Package consumption

The library SHALL be packaged as a pesde package (`patextreme/ptah_libs`,
`luau` target) consumable as a **git dependency pinned to a tag** of this
repository — never published to a registry — and SHALL expose exactly one
library entry whose exports are the named camelCase surface:
`std` (with `predicate`, `gh`, `daemon`, `sessionConfig`, `escalate`, and
`worktree`), `openspec`, `pr`, `issue`, and `factory`. Top-level playbook
exports are named for the entity
they manage; deep-path requires into the library tree SHALL NOT be part of
the supported consumer surface.

#### Scenario: Consumer installs as a git dependency

- **WHEN** a consumer declares a pesde git dependency on this repository at a tag revision and runs `pesde install`
- **THEN** pesde's generated `luau_packages` shim requires the package entry and re-exports its values and types, and the consumer's shim reaches the library through that generated shim

#### Scenario: Entry exports the library surface

- **WHEN** a consumer requires the generated dependency shim
- **THEN** `std.predicate`, `std.gh`, `std.daemon`, `std.sessionConfig`, `std.escalate`, `std.worktree`, `openspec`, `pr`, `issue`, and `factory` (with `factory.new` and `factory.initLabels`) are available on the returned table

#### Scenario: The renamed export replaces the former name

- **WHEN** a consumer requires the generated dependency shim
- **THEN** `prReviewLoop` is not available on the returned table (the rename is a clean break; consumers pin the prior tag to defer it)

## ADDED Requirements

### Requirement: Factory playbook

The library SHALL provide a factory composition playbook that drains a
repository's labeled issue queue into reviewed pull requests by composing
the issue, openspec, and pr playbooks. The factory SHALL construct its
composed playbook instances internally from its own configuration, and
its configuration SHALL NOT accept pre-built playbook instances. Its
Local config SHALL be data only: the work/judge/reporter agent handles
with their ordered session-config entries, the required `queueLabel` with
no default, the optional `claimedLabel`, the required `base` branch with
no default (each issue's worktree branches from `origin/<base>` and its
pull request targets `base`), the free-text `conventions` and
`prContract` prompt fragments injected into the direct-edit and delivery
prompts respectively, and the convergence and bounded-retry caps
(`maxReviewIterations`, `resolveChangeAttempts`,
`openPullRequestAttempts`). The worktree branch for each issue SHALL be
the fixed `issue-<n>`. openspec SHALL be mandatory in v1: each claimed
issue is resolved to an existing openspec change — driven through groom →
implement → verify — or implemented as a direct edit when no change
applies. The factory SHALL expose no dry-run pass-through.

#### Scenario: The consumer shim shrinks to config

- **WHEN** a consumer replaces its factory logic shim with a `factory.new(config)` call
- **THEN** no orchestration code remains in the shim — claiming, worktree provisioning, change resolution, the openspec lifecycle or direct edit, PR opening, the review loop, and teardown are all library-owned

#### Scenario: Required knobs have no defaults

- **WHEN** `factory.new` is called without `queueLabel` or without `base`
- **THEN** construction raises an error naming the missing field (the queue label and the delivery base are the repository's, never the playbook's)

#### Scenario: Prompt fragments travel as data

- **WHEN** a consumer configures `conventions` or `prContract` free text
- **THEN** the library-owned prompt skeletons carry that text at their declared injection points, and the skeletons' structure is unchanged by the fragment's content

#### Scenario: No playbook instances in config

- **WHEN** a consumer's shim config is type-checked against the factory's config
- **THEN** no field accepts an issue, openspec, or pr playbook instance (they are neither data nor ptah runtime handles)

### Requirement: Factory issue-to-PR operation

The factory SHALL provide `issueToPR(number?)`: claim one issue — the
given number only if eligible, otherwise the oldest eligible — provision
its worktree on `issue-<n>` off `origin/<base>`, apply the mapped
openspec change or a direct edit, commit, push, and open the issue-linked
pull request (its body carrying `Closes #<n>` so the issue closes on
merge), and run the convergent PR review loop on the opened PR. The typed
hand-offs SHALL be bounded: the change-resolution hand-off re-asks up to
`resolveChangeAttempts` times and the PR hand-off up to
`openPullRequestAttempts` times, and exhaustion SHALL fail the issue. On
the success path the worktree SHALL be torn down; a failed issue SHALL
keep its worktree as the audit trail and stay claimed.

#### Scenario: Explicit pickup works one issue

- **WHEN** `issueToPR(42)` is called and #42 carries the queue label, is not foreign-assigned, and is unclaimed
- **THEN** exactly #42 is claimed and driven end-to-end, and an ineligible #42 raises with the reason instead

#### Scenario: Scan mode picks the oldest eligible

- **WHEN** `issueToPR()` is called with no number
- **THEN** the oldest eligible issue in the queue is claimed and driven end-to-end

#### Scenario: Direct-edit fallback

- **WHEN** the change-resolution hand-off submits an empty change name for the issue
- **THEN** the issue is implemented by a direct edit in its worktree under the `conventions` fragment, and the pipeline's later steps proceed unchanged

#### Scenario: Hand-off exhaustion fails the issue

- **WHEN** the delivery session submits no PR URL within `openPullRequestAttempts`
- **THEN** the operation fails with a named error, the worktree is kept, and the claim marker remains on the issue

### Requirement: Factory drain loop

The factory SHALL provide `drain()`: repeat the issue-to-PR operation in
scan mode until the queue holds no eligible issue, returning the
collected outcomes. Each issue SHALL run behind a per-issue error
boundary — a failed issue is logged with its failure message and the loop
continues to the next eligible issue — and the stop condition SHALL be
the issue pickup's no-eligible-issue outcome, reported with the scan's
count of eligible issues examined.

#### Scenario: Drains until the queue is empty

- **WHEN** `drain()` runs against a queue holding three eligible issues and no more arrive
- **THEN** three end-to-end runs happen and the returned outcome list carries three entries

#### Scenario: One failure does not stop the drain

- **WHEN** the second of four eligible issues fails mid-run
- **THEN** the failure is logged with the issue number, the remaining two issues are still worked, and all four outcomes appear in the returned list

#### Scenario: Empty queue stops the loop

- **WHEN** `drain()` starts when no issue is eligible
- **THEN** the loop ends immediately with the no-eligible-issue outcome carrying the scanned count

### Requirement: Factory outcomes

The factory SHALL report each issue as outcome data discriminated on
`status`: `pr-reviewed` (PR opened, review loop converged),
`pr-non-converged` (PR opened, review loop reached its cap with open
blocking findings — a completed hand-off to the issue's human reviewer,
never recorded as a failure), `no-eligible-issue` (nothing left to claim,
with the scanned count), and `failed` (the run raised, with the error
message). The PR URL and the review verdict SHALL ride on the
pr-reviewed and pr-non-converged outcomes.

#### Scenario: Non-converged review is a hand-off, not a failure

- **WHEN** the review loop ends non-converged on an opened PR
- **THEN** the outcome is `pr-non-converged` carrying the PR URL and verdict, the worktree is torn down, and the issue waits for its human at merge time

#### Scenario: Failure keeps the audit trail

- **WHEN** any step of the issue's run raises
- **THEN** the outcome is `failed` carrying the error, the worktree is kept in place, and the issue stays claimed

### Requirement: Factory label alignment

The factory module SHALL provide `initLabels(vocabulary?)`: an
agent-free, idempotent alignment of the repository's GitHub labels to a
declared vocabulary of name, color, and description. Alignment SHALL
create the missing labels, update drifted colors and descriptions, never
delete labels outside the vocabulary, and perform no renames. With no
argument it SHALL align the built-in canonical default vocabulary; a
configured vocabulary SHALL replace the default wholesale, never merge
with it. Re-running alignment on an aligned repository SHALL change
nothing.

#### Scenario: Default bootstrap

- **WHEN** `initLabels()` runs on a repository lacking the canonical queue label
- **THEN** `ai-r4d` is created with the canonical color and description

#### Scenario: Drift is corrected

- **WHEN** the queue label exists with a non-canonical color or a missing description
- **THEN** alignment updates the drifted fields to canonical and leaves every other label untouched

#### Scenario: Idempotent re-run

- **WHEN** alignment runs twice in a row
- **THEN** the second run performs no writes

#### Scenario: Configured vocabulary replaces, never merges

- **WHEN** `initLabels` is called with a two-label vocabulary for a repository that uses different label names
- **THEN** exactly the configured labels are aligned and no default-vocabulary label is created

#### Scenario: Unlisted labels survive

- **WHEN** the repository carries labels outside the vocabulary
- **THEN** alignment leaves them unchanged and deletes nothing
