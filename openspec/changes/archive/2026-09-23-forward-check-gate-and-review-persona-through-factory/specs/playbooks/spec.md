# Spec Delta

## MODIFIED Requirements

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
prompts respectively, the convergence and bounded-retry caps
(`maxReviewIterations`, `resolveChangeAttempts`,
`openPullRequestAttempts`), the review-fix loop's check gate and reviewer
instruction (`checks` and `reviewInstruction`, forwarded verbatim into
the internally constructed pr playbook — nil `checks` keeps the gate off
and nil `reviewInstruction` selects the pr playbook's built-in default
persona; the factory adds no default, no rename, and no validation of
its own), and the optional `removeOccupantWorktree` (default `true` —
whether the factory may relocate a live occupant of the issue branch
before provisioning; `false` restores provision's occupant raise). The
worktree branch for each issue SHALL be the fixed `issue-<n>`. openspec
SHALL be mandatory in v1: each claimed issue is resolved to an existing
openspec change — driven through groom → implement → verify — or
implemented as a direct edit when no change applies. The factory SHALL
expose no dry-run pass-through.

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

#### Scenario: Occupant relocation is opt-out

- **WHEN** `factory.new` is called with `removeOccupantWorktree = false`
- **THEN** the factory performs no relocation and an occupied issue branch fails through provision's occupant raise, today's behavior

#### Scenario: The check gate is configurable through the factory

- **WHEN** a consumer configures `checks` on the factory's config
- **THEN** the factory-driven review-fix loop consults check state at the PR head at every convergence decision exactly as when the pr playbook is configured directly — red checks become playbook-owned ledger findings the fix turn resolves, pending checks poll within the budget and end the loop non-converged at exhaustion, and a converged report implies green checks

#### Scenario: The reviewer instruction is configurable through the factory

- **WHEN** a consumer configures `reviewInstruction` on the factory's config
- **THEN** the composed review loop's review sessions run under that persona in place of the built-in default

#### Scenario: Unset review fields change nothing

- **WHEN** `factory.new` is called without `checks` or without `reviewInstruction`
- **THEN** the composed review-fix loop behaves exactly as before this change — the gate is off (no check state is read) and the built-in default persona is used
