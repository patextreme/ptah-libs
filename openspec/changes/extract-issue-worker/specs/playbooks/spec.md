# playbooks Specification (delta)

## MODIFIED Requirements

### Requirement: Package consumption

The library SHALL be packaged as a pesde package (`patextreme/ptah_libs`,
`luau` target) consumable as a **git dependency pinned to a tag** of this
repository — never published to a registry — and SHALL expose exactly one
library entry whose exports are the named camelCase surface:
`std` (with `agent`, `shell`, `predicate`, `gh`, `daemon`, `sessionConfig`,
and `escalate`), `openspec`, `prReviewLoop`, `issueWorker`, and `ciGate`.
Deep-path requires into the library tree SHALL NOT be part of the supported
consumer surface.

#### Scenario: Consumer installs as a git dependency

- **WHEN** a consumer declares a pesde git dependency on this repository at a tag revision and runs `pesde install`
- **THEN** pesde's generated `luau_packages` shim requires the package entry and re-exports its values and types, and the consumer's shim reaches the library through that generated shim

#### Scenario: Entry exports the library surface

- **WHEN** a consumer requires the generated dependency shim
- **THEN** `std.agent`, `std.shell`, `std.predicate`, `std.gh`, `std.daemon`, `std.sessionConfig`, `std.escalate`, `openspec`, `prReviewLoop`, `issueWorker`, and `ciGate` are available on the returned table

## ADDED Requirements

### Requirement: Agent directory scoping

The library SHALL provide `std.agent`, exposing an operation that takes an
agent handle and a directory and returns a handle whose sessions all run with
that directory as their working directory. The returned handle SHALL satisfy
the same structural agent contract as the handle it wraps, so it is accepted
anywhere an agent handle is accepted — including the library's own playbooks,
which take no `cwd`. The wrapped directory SHALL be applied to every session
unconditionally, overriding any `cwd` supplied in the session options at the
call site. The operation SHALL NOT construct an agent; a library module SHALL
NOT call `ptah.agent` literally, so requiring the library never becomes a
pre-flight finding for a consumer whose registry lacks a given agent name.

#### Scenario: Wrapped handle pins every session

- **WHEN** a consumer wraps an agent handle with a directory and creates sessions both with and without a `cwd` in the options
- **THEN** every session created through the wrapped handle runs with the wrapped directory as its working directory

#### Scenario: Wrapped handle is accepted where an agent handle is

- **WHEN** a consumer passes the wrapped handle as a playbook's `agent` config value
- **THEN** the playbook's sessions run in the wrapped directory without the playbook accepting a `cwd` of its own

#### Scenario: Requiring the library constructs no agent

- **WHEN** a consumer whose registry does not define any particular agent name requires the library and runs `ptah check`
- **THEN** no agent-name finding is reported for a literal `ptah.agent` call inside the library

### Requirement: Shell helpers

The library SHALL provide `std.shell`, a repo-agnostic set of helpers over
ptah's exec: a two-sided whitespace trim; POSIX-safe single-quoting of an
argument value, escaping embedded single quotes so values containing spaces or
quotes reach the command verbatim; a run operation for commands whose only
acceptable outcome is success, returning trimmed stdout and raising a script
error carrying the exit code and stderr otherwise; a boolean success probe;
and a normalization of a caught error value to a message string. The library's
GitHub transport and daemon skeleton SHALL use these helpers rather than
private copies, so quoting and trim semantics cannot drift between modules.

#### Scenario: Failure raises where success is required

- **WHEN** a command whose only acceptable outcome is success exits non-zero
- **THEN** the operation raises a script error naming the command, its exit code, and its stderr

#### Scenario: Any exit code is data for the probe

- **WHEN** the success probe runs a command that exits non-zero
- **THEN** it returns false and does not raise

#### Scenario: Values with quotes pass through verbatim

- **WHEN** an argument value contains spaces and single quotes
- **THEN** the quoted command passes the value to the command verbatim

### Requirement: issueWorker meta playbook

The library SHALL provide an `issueWorker` **meta playbook**: a playbook that
composes stdlib helpers, other playbooks, and deterministic stages to take one
GitHub issue from pickup to a reviewed, CI-green pull request. One run
processes at most one issue and leaves nothing running between runs.

The playbook's config SHALL be data plus declared agent handles, and SHALL
NOT contain callable hooks. It SHALL accept the role handles `agent`,
`judgeAgent`, and `reporterAgent`, and the ordered session-config arrays
`sessionConfig`, `judgeSessionConfig`, and `reporterSessionConfig`, following
the library's session-config convention. It SHALL accept the required repo
shape `readyLabel` and `blockedLabel` (the library SHALL ship no default,
encoding no repository's label), `baseBranch`, `branchPrefix`, and
`worktreeDir`; the deterministic knobs `gateCommands`, `commitSignArgs`, and
the caps (`pickupLimit`, `maxAttempts`, `reviewMaxIterations`, and the CI
bounds); an opt-in `openspec` flag; and an optional `repoBrief` string.
`repoBrief` SHALL be injected into the playbook's built-in stage prompts so
repository prose (a pointer to `AGENTS.md`, the environment it runs in, a
merge-not-rebase policy) arrives as data while the prompts stay playbook-owned;
its absence SHALL leave the built-in prompts otherwise unchanged.

The instance SHALL expose three operations: `run()`, which performs pickup and,
when an issue is eligible, the whole lifecycle, returning the outcome;
`pickup()`, which returns the claimed issue or nil; and `process(issue)`,
which runs a claimed issue through to delivery or rejection and returns the
outcome. The outcome SHALL be a typed discriminated record with status
`delivered`, `rejected`, `idle`, or `failed`, carrying the issue, the pull
request URL where one exists, and a reason on rejection or failure.

The playbook SHALL own its bookkeeping and SHALL return a `failed` outcome
after recording a stage failure rather than propagating the error; it SHALL
NOT call `ptah.exit` or `ptah.ask` literally, and it SHALL NOT construct an
agent. Every session the playbook creates — its own stage sessions and those
of the nested playbooks it drives — SHALL run in the per-issue worktree,
established by wrapping the configured handle once per issue rather than by
setting `cwd` at individual sessions.

When `openspec` is not enabled, the triage routes SHALL exclude the openspec
route and the playbook SHALL require no openspec environment.

#### Scenario: One issue per run

- **WHEN** the playbook runs and an eligible issue exists
- **THEN** it processes exactly that issue and returns a terminal outcome

#### Scenario: Nothing to do

- **WHEN** the playbook's `run` operation finds no eligible issue
- **THEN** it returns an `idle` outcome and performs no repository mutation

#### Scenario: A stage failure is recorded, not propagated

- **WHEN** a stage fails after an issue was claimed
- **THEN** the playbook performs the failure bookkeeping and returns a `failed` outcome carrying the reason, and the shim — not the playbook — decides the exit code

#### Scenario: Config is validated by the compatibility gate

- **WHEN** a consumer shim passes a config table missing a required field or with a wrong-typed field and runs `ptah check`
- **THEN** check reports a type error naming the offending field

#### Scenario: Repository prose is data

- **WHEN** the playbook is configured with a `repoBrief` string and a stage runs
- **THEN** the built-in stage prompt carries that text, and a run without `repoBrief` uses the unchanged built-in prompt

#### Scenario: openspec is opt-in

- **WHEN** the playbook is configured without the openspec flag
- **THEN** triage offers only the direct and reject routes and the run requires no openspec CLI or skills

#### Scenario: All sessions run in the issue worktree

- **WHEN** the playbook drives its own stages and the nested openspec and pr-review-loop playbooks for an issue
- **THEN** every session runs with the per-issue worktree as its working directory, and no stage sets `cwd` itself

#### Scenario: Pickup and process compose

- **WHEN** a consumer calls `pickup` and then `process` on the returned issue
- **THEN** the same lifecycle runs as `run`, without the consumer re-triggering pickup

### Requirement: Issue pickup and claim

The playbook SHALL select open issues carrying the configured ready label,
oldest first, and SHALL claim the first eligible issue by assigning the
authenticated user, so an already-assigned issue is never eligible. It SHALL
skip an issue whose issue branch already has an open pull request, and an
issue whose branch exists without its worktree. The ready label SHALL remain
on the issue after the claim (it marks readiness to others; the assignee is
the claim). The playbook SHALL ensure the ready and blocked labels exist
before listing, creating each idempotently when missing. A claim lost to a
concurrent run SHALL cause the issue to be skipped rather than failing the
run.

#### Scenario: Oldest eligible issue is claimed

- **WHEN** several open unassigned issues carry the ready label
- **THEN** the oldest by creation time is claimed and processed

#### Scenario: In-flight delivery is skipped

- **WHEN** an issue's branch already has an open pull request
- **THEN** the issue is skipped and the next eligible issue is considered

#### Scenario: Already-assigned issue is skipped

- **WHEN** an issue carrying the ready label already has an assignee
- **THEN** it is not eligible to be claimed

#### Scenario: Claim lost to a concurrent run

- **WHEN** assigning the authenticated user fails because another run claimed the issue
- **THEN** the playbook skips that issue and continues with the next candidate

#### Scenario: Labels are created idempotently

- **WHEN** the ready or blocked label does not exist in the repository
- **THEN** the playbook creates it, and an existing label is left as is

### Requirement: Triage routes and planning

The playbook SHALL run one triage session in the issue worktree that returns a
typed verdict through the session's result: a route, a rationale, a
conventional-commit type, and — on the openspec route — a change name. A
verdict that is missing or invalid SHALL be retried a bounded number of times,
and exhaustion SHALL fail the run. The route SHALL be `direct` or `reject`,
and additionally `openspec` only when the openspec opt-in is enabled. On the
openspec route the playbook SHALL require that the named change directory
exists before driving the openspec playbook's groom, implement, and verify
operations, and SHALL fail the run if it does not. On the direct route one
session SHALL implement the issue in the worktree and commit the work with the
configured signing arguments. On the reject route the playbook SHALL perform
the blocked bookkeeping and return a `rejected` outcome without delivering.

#### Scenario: Invalid verdict is retried

- **WHEN** the triage session submits no typed result, or a result missing a route, rationale, or commit type
- **THEN** the playbook re-prompts up to the retry bound and fails the run if no valid verdict arrives

#### Scenario: Direct route implements and commits

- **WHEN** triage returns the direct route
- **THEN** one session implements the issue in the worktree and commits with the configured signing arguments, and no pull request is opened by that session

#### Scenario: Reject route blocks without delivering

- **WHEN** triage returns the reject route
- **THEN** the playbook records the rationale as blocked bookkeeping and returns a `rejected` outcome

#### Scenario: openspec route requires its change

- **WHEN** triage returns the openspec route with a change name but the change directory does not exist in the worktree
- **THEN** the run fails with an error naming the missing change

#### Scenario: openspec route drives the openspec playbook

- **WHEN** triage returns the openspec route and the change exists
- **THEN** the playbook runs the openspec playbook's groom, implement, and verify operations for that change, in order, in the worktree

### Requirement: Delivery contract

The playbook SHALL deliver the issue branch through one session that runs the
configured gate commands, brings the branch up to date with the base branch by
merging — never rebasing, so signed commits are preserved — pushes the branch,
and opens a pull request against the base branch whose body begins with the
issue's closing reference and whose title is the configured
conventional-commit type composed with the issue title. The session SHALL
submit the pull request URL as a typed result, retried a bounded number of
times. Before the pull request is handed onward, the playbook SHALL
deterministically re-check that the branch has at least one commit ahead of
the base branch, that the reported URL is a pull URL, and that the pull
request's title matches the composed title — correcting the title through the
transport and failing the run if it cannot be corrected.

#### Scenario: Delivery re-checks are deterministic

- **WHEN** the delivery session reports a pull request URL
- **THEN** the playbook re-checks commits-ahead, the URL shape, and the title itself rather than trusting the session's prose

#### Scenario: Branch with no commits ahead fails delivery

- **WHEN** the delivered branch has no commits ahead of the base branch
- **THEN** the run fails with an error naming the branch

#### Scenario: Title is corrected or fails

- **WHEN** the opened pull request's title differs from the composed conventional-commit title
- **THEN** the playbook edits the title and fails the run if it still does not match

#### Scenario: No rebase

- **WHEN** the branch is behind the base branch and the session brings it up to date
- **THEN** the branch is merged, not rebased

### Requirement: Issue bookkeeping

Every GitHub write outside the pull request SHALL be performed by the
playbook, never an agent, so every run leaves the same paper trail. On success
the playbook SHALL comment the pull request URL on the issue and leave the
ready label and claim in place. On rejection or failure it SHALL comment the
reason, remove the ready label, add the blocked label, and release the claim
by removing the assignee, so a human can re-queue the issue by swapping the
labels back.

#### Scenario: Success comments the pull request

- **WHEN** an issue is delivered
- **THEN** the playbook comments the pull request URL on the issue and leaves the ready label and assignee in place

#### Scenario: Blocked bookkeeping releases the claim

- **WHEN** an issue is rejected or the run fails
- **THEN** the playbook comments the reason, swaps the ready label for the blocked label, and removes the assignee

### Requirement: CI gate playbook

The library SHALL provide a `ciGate` playbook that watches a pull request's
check rollup to a terminal state and, while failing checks remain and a repair
budget remains, hands the failing run's logs to a configured agent for a
signed repair push. It SHALL classify each rollup entry across the check-run
and status-context shapes and SHALL proceed only when every entry is
successful or neutral. The playbook SHALL accept an `agent` handle, an ordered
`sessionConfig` array, a wait budget, a poll interval, and a repair-attempt
cap. Its `watch` operation SHALL take the pull request URL and return a typed
outcome — `green` when every check passed, otherwise `unresolved` carrying the
attempt count and a reason — rather than raising on exhaustion or timeout. The
playbook SHALL NOT ask a human: a red check is either agent-fixable or
environmental, and the calling script owns the policy for an unresolved
outcome.

#### Scenario: Green checks proceed

- **WHEN** every entry in the pull request's check rollup is successful, neutral, or skipped
- **THEN** `watch` returns a `green` outcome

#### Scenario: Red checks are repaired

- **WHEN** a check run fails and the repair budget remains
- **THEN** the playbook hands the failing logs to the agent for a signed repair push and re-watches the rollup

#### Scenario: Repair budget exhausted

- **WHEN** checks remain red after the configured repair attempts
- **THEN** `watch` returns an `unresolved` outcome carrying the attempt count rather than raising

#### Scenario: Wait budget exhausted

- **WHEN** checks have not reached a terminal state within the wait budget
- **THEN** `watch` returns an `unresolved` outcome naming the timeout rather than raising

#### Scenario: Status contexts and check runs are both classified

- **WHEN** the check rollup mixes check-run entries and status-context entries
- **THEN** each entry's conclusion, state, and status are classified so pending entries do not read as failures
