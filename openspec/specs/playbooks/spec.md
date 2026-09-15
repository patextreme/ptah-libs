# playbooks Specification

## Purpose
The shared workflow library (Ptah Playbooks): repo-agnostic stdlib
helpers and composable workflow playbooks, packaged for consumption as a
pesde git dependency and driven by consumers through thin shims.

## Requirements

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

### Requirement: Session config application

The library SHALL provide a shared session-config mechanism: an ordered
array of entries, each carrying an option `id` and a `value` of string or
boolean, applied to a session as `setConfig` calls in declared order after
session creation and before the session's first prompt. The array is the
consumer's `setConfig` call sequence expressed as data. The mechanism SHALL
export the entry type and the apply operation so consumers building their
own playbooks use it verbatim, and the library's own playbooks and judge
SHALL use it so application semantics cannot drift.

A nil or empty entry array SHALL apply nothing. Duplicate ids SHALL apply
verbatim in order (the later entry wins, exactly as repeated runtime
`setConfig` calls would). An agent-rejected entry SHALL fail through the
existing `setConfig` error path — a catchable error carrying the option id
and the agent's message — and entries applied before the rejection SHALL
remain applied.

#### Scenario: Entries apply in declared order

- **WHEN** a session is configured with entries `{ id = "model", value = "opus" }` followed by `{ id = "effort", value = "high" }`
- **THEN** the session receives the two `setConfig` calls in exactly that order before its first prompt

#### Scenario: Omitted or empty entry array is a no-op

- **WHEN** a playbook or judge is configured without session-config entries, or with an empty array
- **THEN** no `setConfig` calls are issued and the session's behavior is otherwise unchanged

#### Scenario: Duplicate ids apply verbatim

- **WHEN** the configured entries contain the same id twice with different values
- **THEN** both apply in declared order and the later value is the effective one, matching repeated runtime `setConfig` calls

#### Scenario: Agent rejection fails through the existing error path

- **WHEN** the agent rejects a configured entry's `setConfig`
- **THEN** the operation raises the `setConfig` error carrying the option id and the agent's message, and entries applied before the rejection remain applied

#### Scenario: Malformed entries are a check finding

- **WHEN** a consumer shim declares a session-config entry with a wrong-typed value or a missing id and runs `ptah check`
- **THEN** check reports a type error naming the entry shape

### Requirement: Typed judge

The library SHALL provide a typed boolean judge that asks a designated
judge agent whether a predicate holds for a payload and returns the verdict
from the session's typed boolean result. The judge's options SHALL accept
an agent handle, a session id, a retry bound, and an optional ordered array
of session-config entries applied to every judge attempt session before
its prompt; no dedicated model field SHALL exist (a model choice is an
ordinary session-config entry). A judge that submits no verdict SHALL be
retried a bounded number of times, and exhaustion SHALL be a script error,
never a hang or a silent default.

#### Scenario: Verdict returned

- **WHEN** the judge session submits a boolean verdict for the predicate and payload
- **THEN** the operation returns that verdict

#### Scenario: Judge never answers

- **WHEN** the judge session submits no typed verdict on every attempt up to the bound
- **THEN** the operation raises a script error naming the judge and the attempt count

#### Scenario: Judge sessions receive configured entries

- **WHEN** the judge is invoked with session-config entries
- **THEN** every attempt session receives the entries in declared order before the predicate prompt

### Requirement: GitHub CLI transport

The library SHALL provide a GitHub transport that shells out to the `gh` CLI
via ptah's exec, returning a structured outcome (exit code, stdout, parsed
JSON when requested) instead of raising, and SHALL quote arguments so values
containing spaces or quotes are passed through verbatim.

#### Scenario: Command succeeds with JSON output

- **WHEN** a `gh` invocation exits zero and JSON output is requested
- **THEN** the transport returns a success outcome carrying the parsed JSON value

#### Scenario: Command fails

- **WHEN** a `gh` invocation exits non-zero
- **THEN** the transport returns a failure outcome carrying the exit code and stderr, and the calling script keeps running

### Requirement: Daemon loop skeleton

The library SHALL provide a repo-loop skeleton that applies a per-repo
operation to every configured repository, isolates each repository behind an
error boundary so one raising repository cannot abort the others, and
supports both sequential and bounded-concurrency parallel execution.

#### Scenario: One repository raises

- **WHEN** the per-repo operation raises for one of several configured repositories
- **THEN** the loop records that repository's failure and completes the remaining repositories

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

### Requirement: Playbook facade contract

Every workflow playbook SHALL be a module exposing a constructor that
accepts a data config table and returns an instance whose methods are the
playbook's typed operations; config SHALL NOT contain callable hooks.
Data config SHALL include arrays of typed data records (e.g. ordered
session-config entries) wherever the playbook's exported config type
declares them. Ptah runtime handles (e.g. agent handles) SHALL be permitted
as config values where the playbook's exported config type declares them.
Playbooks and stdlib modules SHALL be strict-mode typed so that `ptah check`
in a consumer repo validates the consumer's config against the playbook's
config type.

#### Scenario: Consumer config mismatches the playbook type

- **WHEN** a consumer shim passes a config table that does not satisfy the playbook's exported config type and runs `ptah check`
- **THEN** check reports a type error naming the offending field

#### Scenario: Per-call data is a method argument

- **WHEN** a consumer calls a playbook operation that acts on a specific item (e.g. a change name or PR URL)
- **THEN** the item is supplied as a method argument, not baked into the playbook's config

#### Scenario: Agent handle accepted as config

- **WHEN** a consumer constructs an agent handle (from a registry name or an inline agent spec) and passes it in a config field the playbook's config type declares as an agent handle
- **THEN** the playbook drives that role's sessions through the supplied handle and performs no agent construction of its own

#### Scenario: Callable hook rejected by the type gate

- **WHEN** a consumer shim passes a config containing an arbitrary function in a config field and runs `ptah check`
- **THEN** check reports a type error naming the offending field

#### Scenario: Ordered entries are data config

- **WHEN** a consumer configures a playbook's declared session-config field with an ordered array of entry records
- **THEN** the configuration is accepted as data config and validated against the field's declared entry type

### Requirement: Library self-containment

Library modules SHALL only require other modules within the library tree, so
the tree works installed at any path a package manager places it; they SHALL
NOT write files inside the library tree; and they SHALL NOT invoke exec with
a relative working directory — repository-relative paths MUST arrive through
config.

#### Scenario: Installed at an arbitrary path

- **WHEN** the library tree is installed at any path a package manager chooses (e.g. inside a consumer's package store) and a shim requires the package entry
- **THEN** the entry and every library module's internal requires resolve without reference to the install location

#### Scenario: Library tree is read-only

- **WHEN** a playbook runs from a read-only install (e.g. the nix store)
- **THEN** the workflow completes without attempting to write inside the library tree

### Requirement: Escalation mechanism

The library SHALL provide a best-effort escalation mechanism (`std.escalate`)
that routes a blocker to a human through ptah's ask facility when one is
available and reports the outcome as data. The mechanism SHALL expose one
operation taking a required prompt line and optional details, and SHALL
return a status-discriminated outcome: `respond` carrying the human's
answer text unprocessed, `abort` when the human refused the ask, or
`unavailable` carrying the underlying reason when no ask provider could
serve the request (prohibited, unconfigured, provider failure, or end of
input). The mechanism SHALL invoke ptah's ask through an aliased reference
rather than a literal call site, so that a library-level ask never becomes
a pre-flight finding that blocks a consumer's `ptah check` or `ptah run`
in an environment without an ask provider. The mechanism SHALL accept no
configuration: ask-provider selection remains the operator's decision,
made outside script code.

#### Scenario: Human answer is returned as data

- **WHEN** the escalation operation is invoked where an ask provider serves the request and the human answers
- **THEN** the outcome is `respond` carrying the answer text verbatim

#### Scenario: Human refusal is returned as data

- **WHEN** the escalation operation is invoked where an ask provider serves the request and the human aborts the ask
- **THEN** the outcome is `abort` carrying no answer text

#### Scenario: Unservable ask degrades to an unavailable outcome

- **WHEN** the escalation operation is invoked where no ask provider serves the request — asking is prohibited, no provider is configured, the provider fails, or the input closes without an answer
- **THEN** the outcome is `unavailable` carrying the provider's reason, and no error propagates from the ask itself

#### Scenario: Consumer checks are unaffected by the library's ask

- **WHEN** a consumer shim requires the library and runs `ptah check` or `ptah run` pre-flight in an environment with no ask provider configured
- **THEN** no ask-related finding is reported for the library's escalation mechanism

### Requirement: openspec playbook

The library SHALL provide an openspec playbook whose instance exposes
groom, implement, and verify operations on a named change: groom converges a
change's proposals through review, implement drives task execution, and
verify converges verification then syncs and archives the change. The
playbook SHALL declare its environment requirements (an agent carrying the
openspec skills, `openspec` on PATH) in its documentation rather than
bundling or installing them. Convergence is the playbook's own loop over
the library's typed judge: a judge-rejected pass probes for human input;
a confirmed need for human input escalates through the library's escalation
mechanism — a served ask resumes the loop with the human's answer, and an
unservable or refused ask fails the operation without issuing a fix — and
exhausting the iteration cap fails the operation with an error reporting
the cap.

On a confirmed need for human input, the playbook SHALL ask through the
library's escalation mechanism with an ask whose prompt line identifies
the operation, the change, and the iteration state, and whose details
carry the work session's label and the full probe text. When the ask is
answered, the answer text SHALL be sent verbatim as the next prompt of
the still-open work session (no header or framing added), the iteration
SHALL count against the cap, and the loop SHALL continue toward
convergence. When the human aborts the ask, the operation SHALL fail with
a distinct error stating the human aborted the escalation. When no ask
provider serves the request, the operation SHALL fail with an error
stating human input is needed — the same wording as before the ask
existed.

The playbook's config SHALL accept `sessionConfig`, an ordered
session-config entry array applied to every work session the playbook
creates — every per-iteration session of groom, implement, and verify, and
verify's archive session — and `judgeSessionConfig`, applied to every judge
and human-escalation-probe session. The `model` and `judgeModel` config
fields SHALL NOT exist: a model choice is an ordinary `sessionConfig`
entry, and the entry order is the consumer's `setConfig` order.

implement SHALL accept an optional task scope: free text describing the
subset of the change's tasks the run is responsible for. When a scope is
given, the work prompt SHALL instruct the agent to treat the scoped tasks
as the entire job and leave all other tasks pending, and the loop's
acceptance SHALL be judged against the scope rather than against the
whole change. The scope SHALL be carried to the judge so the verdict is
made against the scoped completion, without the judge needing the work
prompt. A scope that matches no tasks SHALL end the pass with a stated
dead-end rather than the agent substituting a different subset, and the
escalation path SHALL surface it (an ask when a provider serves it; an
operation error otherwise).
groom and verify SHALL remain whole-change operations.

#### Scenario: Verify converges and archives

- **WHEN** verify runs on a change whose implementation passes the verification judge
- **THEN** the verification loop exits and the sync-and-archive step runs as part of the same operation

#### Scenario: Missing environment requirement

- **WHEN** the playbook's documentation is consulted for its environment requirements
- **THEN** the agent-skill and CLI requirements are listed so a consumer can verify them before running

#### Scenario: Human escalation

- **WHEN** a groom pass is judge-rejected and the escalation judge confirms human input is required
- **THEN** the need escalates through the library's escalation mechanism — an answered ask resumes the loop with the human's answer; an aborted or unservable ask fails the operation with an error stating human input is needed, and no fix prompt is issued

#### Scenario: Human escalation asks and resumes

- **WHEN** a groom pass is judge-rejected, the escalation judge confirms human input is required, an ask provider serves the request, and the human answers
- **THEN** the answer is sent verbatim as the next prompt of the still-open work session, the iteration counts against the cap, and the loop continues toward convergence

#### Scenario: Human escalation abort fails

- **WHEN** a groom pass is judge-rejected, the escalation judge confirms human input is required, an ask provider serves the request, and the human aborts the ask
- **THEN** the operation fails with a distinct error stating the human aborted the escalation, and no fix prompt is issued

#### Scenario: Unservable ask fails as before

- **WHEN** a groom pass is judge-rejected, the escalation judge confirms human input is required, and no ask provider serves the request
- **THEN** the operation fails with an error stating human input is needed — the same wording as before the ask existed — and no fix prompt is issued

#### Scenario: Ask carries identity, session label, ACP session id, and full probe text

- **WHEN** the playbook raises an escalation ask
- **THEN** the prompt line identifies the operation, the change, and the iteration state, and the details carry the work session's label, the agent-side ACP session id, and the full probe text without truncation

#### Scenario: Iteration cap

- **WHEN** every pass is judge-rejected and the findings stay fixable up to the configured iteration cap
- **THEN** the operation fails with an error reporting the cap was reached

#### Scenario: Scoped implement completes the subset

- **WHEN** implement runs with a task scope and the agent implements the tasks matching that scope
- **THEN** the judge accepts the pass and the operation exits successfully while tasks outside the scope remain pending

#### Scenario: Scopeless implement is unchanged

- **WHEN** implement runs without a task scope
- **THEN** the prompts, judge acceptance, and log lines are identical to the behavior before task scopes existed, with completion judged against all tasks of the change

#### Scenario: Unresolvable scope dead-ends

- **WHEN** implement runs with a task scope that matches no tasks of the change
- **THEN** the agent ends the pass stating that the scope matches no tasks without implementing a substitute subset, and the dead-end surfaces through the escalation path (an ask when a provider serves it; the operation fails otherwise)

#### Scenario: Work sessions receive session config

- **WHEN** the playbook is configured with `sessionConfig` entries and any operation runs
- **THEN** every per-iteration work session, and verify's archive session, receives the entries in declared order before its first prompt

#### Scenario: Judge and probe sessions receive judge session config

- **WHEN** the playbook is configured with `judgeSessionConfig` entries and any operation runs
- **THEN** every judge session and every human-escalation-probe session receives the entries in declared order before its prompt

#### Scenario: Removed model field is a type error

- **WHEN** a consumer shim configures the removed `model` or `judgeModel` field and runs `ptah check`
- **THEN** check reports a type error naming the unknown field, steering the consumer to the `sessionConfig` entry form

### Requirement: PR review loop playbook

The library SHALL provide a PR review loop playbook that runs a convergent
review→validate→fix→verify loop against a pull request, with repository-specific
settings expressed as config rather than code. The target repository SHALL NOT be
playbook config: it arrives per call inside the PR URL. The playbook SHALL NOT read
CI results or execute repo-specific gate commands; deterministic signal ingestion and
post-loop policy are the calling script's responsibility. The playbook SHALL document
this boundary.

The loop's first review pass against a PR without an existing ledger is a full-PR
review (discovery). Every subsequent review pass SHALL be a delta review: the review
prompt carries the ledger's `lastReviewedSha` and directs the reviewer to review only
the changes since that commit and report recurrences by ledger finding id rather than
refiling them.

The work session reviews freely in prose following its persona instruction and SHALL
validate blocking findings with its own in-session subagents before finalizing its
review. The directive to do so SHALL be carried by the component-owned protocol
fragment, not the configurable persona, so a persona replacement cannot remove it.
The playbook SHALL convert the work session's prose into structured data
through a typed judge session (a `resultSchema` result): the judge SHALL receive the
review prose, the ledger state, the PR's intention, and the configured
`blockingAdditions` text, and SHALL return typed findings carrying per-finding
severity (blocking or non-blocking), a family name, a validation status, and the
judge's `needsHuman` determination, together with a reconciliation of the ledger's
open findings (resolved, with evidence, or still open). The judge SHALL steer
findings against the PR's intention: a finding the judge rates important but outside
the PR's scope SHALL be recorded with a deferred status in the ledger, SHALL NOT gate
convergence, and SHALL be surfaced in the PR review report's deferred list. A judge
that submits no typed result SHALL be retried a bounded number of times, and
exhaustion SHALL fail the iteration — never a silent converge. The judge agent is a
required config handle: the loop's convergence depends on it, and no prose-parsing
fallback replaces it.

Convergence SHALL be computed from the judge's typed output: the loop converges when
no open blocking findings remain. The loop's budget is a single
`maxIterations` cap (default 8) over review passes. A fix turn SHALL be issued only
when open blocking findings exist and budget remains; when the cap is reached with
open findings, the loop SHALL NOT fix — it SHALL end and report a non-converged
outcome. Every pushed fix is therefore followed by at least one review pass. A fix
turn SHALL address all open blocking findings in one turn, by root cause, and SHALL
commit and push (gated by dry-run).

The work session SHALL NOT post to the pull request. For every terminal outcome that
returns (converged or non-converged), the playbook SHALL produce a PR review report
per the PR review report requirement.

The loop's only escalation trigger is the judge's `needsHuman` flag. When flagged,
the loop SHALL ask through the library's escalation mechanism with an ask whose prompt
line identifies the loop and the PR URL and the iteration state, and whose details
carry the work session's label and the full review prose. When the ask is answered,
the answer text SHALL be sent verbatim as the next prompt of the still-open work
session (no header or framing added), the commit-and-push step SHALL still follow the
human-guided fix (gated by dry-run as any fix), the iteration SHALL count against the
cap, and the loop SHALL continue toward convergence. When the human aborts the ask,
the operation SHALL fail with a distinct error stating the human aborted the
escalation. When no ask provider serves the request, the operation SHALL fail with an
error stating human input is needed to resolve the findings.

The playbook's config SHALL accept `agent` and the required `judgeAgent` and
`reporterAgent` handles, `sessionConfig` (applied to every work session the playbook
creates), `judgeSessionConfig` (applied to every judge session),
`reporterSessionConfig` (applied to every reporter session), `reviewInstruction`
(persona, per the instruction contract), `blockingAdditions` (free text supplied to
the judge defining what counts as blocking for the repository), `dryRun`, and
`maxIterations` (default 8). The `model` and `judgeModel` config fields
SHALL NOT exist: a model choice is an ordinary `sessionConfig` entry, and the entry
order is the consumer's `setConfig` order.

The `review` operation SHALL return a typed outcome carrying a status
(`converged` / `non-converged`), the final verdict text, the final ledger snapshot,
and the posted report text (`report`) — outcomes as data, matching the library's
transport conventions — rather than a bare verdict string. Escalation failures do not appear in the outcome: an
aborted or unservable ask fails the operation with an error, and an answered ask
continues the loop toward convergence, so the returned status is always
`converged` or `non-converged`.

#### Scenario: First pass reviews the whole PR

- **WHEN** the loop reviews a PR with no existing ledger
- **THEN** the first review pass targets the entire PR and its result is recorded in a new ledger with the discovery SHA and the PR's intention

#### Scenario: Later passes review only the delta

- **WHEN** the loop runs a review pass after a fix has been pushed
- **THEN** the review prompt carries the ledger's `lastReviewedSha` and directs the reviewer to review only the changes since that commit and to report recurrences by ledger finding id, and the ledger's `lastReviewedSha` advances

#### Scenario: Judge converts prose to typed findings

- **WHEN** the work session completes a review in prose
- **THEN** a typed judge session receives the prose, the ledger, the PR intention, and the configured `blockingAdditions`, and returns structured findings (severity, family, validation status, `needsHuman`) plus a reconciliation of the ledger's open findings

#### Scenario: Convergence is computed from typed findings

- **WHEN** the judge's typed output reports no open blocking findings
- **THEN** the loop converges and the playbook produces a PR review report whose status line reports convergence

#### Scenario: Review finds fixable findings

- **WHEN** the judge's typed output reports open blocking findings and budget remains, and the judge does not flag `needsHuman`
- **THEN** the work session is prompted to resolve all of them in one fix turn addressing the root cause, followed by commit-and-push (gated by dry-run), iterating until the review converges or escalation occurs

#### Scenario: Fix never consumes the last unit

- **WHEN** the judge reports open blocking findings and the iteration cap has been reached
- **THEN** no fix turn is issued; the loop ends, the operation returns a non-converged outcome carrying the verdict text, the ledger snapshot, and the report text, and the playbook produces a non-converged PR review report

#### Scenario: Judge exhaustion fails the iteration

- **WHEN** the judge session submits no typed result on every attempt up to the bound
- **THEN** the iteration fails with a script error naming the judge and the attempt count, and no fix turn is issued

#### Scenario: Validation happens in the work session

- **WHEN** the reviewer reports blocking findings during a review pass
- **THEN** the review prompt carries the component-owned protocol fragment's in-session validation directive, the work session validates the findings with its own in-session subagents, and the validation outcomes reach the judge as part of the review prose

#### Scenario: Deferred findings do not gate convergence

- **WHEN** the judge defers a finding as important but outside the PR's intention
- **THEN** the finding is recorded with a deferred status, the loop may converge with it open, and the PR review report lists it under deferred findings

#### Scenario: Human escalation asks and resumes

- **WHEN** the judge flags `needsHuman`, an ask provider serves the request, and the human answers
- **THEN** the answer is sent verbatim as the next prompt of the still-open work session, the commit-and-push step follows the human-guided fix (gated by dry-run as any fix), the iteration counts against the cap, and the loop continues toward convergence

#### Scenario: Human escalation abort fails

- **WHEN** the judge flags `needsHuman`, an ask provider serves the request, and the human aborts the ask
- **THEN** the operation fails with a distinct error stating the human aborted the escalation, and no fix is issued

#### Scenario: Unservable ask fails as before

- **WHEN** the judge flags `needsHuman` and no ask provider serves the request
- **THEN** the operation fails with an error stating human input is needed to resolve the findings — the same wording as before the ask existed — and no fix is issued

#### Scenario: Ask carries identity, session label, ACP session id, and full probe text

- **WHEN** the loop raises an escalation ask
- **THEN** the prompt line identifies the loop, the PR URL, and the iteration state, and the details carry the work session's label, the agent-side ACP session id, and the full review prose (the probe payload in this design) without truncation

#### Scenario: Repository context is per-call

- **WHEN** the loop reviews a pull request
- **THEN** the repository context comes from the PR URL passed to the operation, and the playbook's config declares no repository field

#### Scenario: Config surface

- **WHEN** a consumer constructs the playbook
- **THEN** the config accepts `agent`, the required `judgeAgent` and `reporterAgent`, `sessionConfig`, `judgeSessionConfig`, `reporterSessionConfig`, `reviewInstruction`, `blockingAdditions`, `dryRun`, and `maxIterations` (default 8), and the removed `model`/`judgeModel` fields are nil-typed so configuring one is a check error

#### Scenario: Work sessions receive session config

- **WHEN** the playbook is configured with `sessionConfig` entries and the review loop runs
- **THEN** every per-iteration work session receives the entries in declared order before its first prompt

#### Scenario: Judge and probe sessions receive judge session config

- **WHEN** the playbook is configured with `judgeSessionConfig` entries and the review loop runs
- **THEN** every judge session receives the entries in declared order before its prompt

#### Scenario: Removed model field is a type error

- **WHEN** a consumer shim configures the removed `model` or `judgeModel` field and runs `ptah check`
- **THEN** check reports a type error naming the unknown field, steering the consumer to the `sessionConfig` entry form

#### Scenario: Operation returns a typed outcome

- **WHEN** the `review` operation ends — converged, or non-converged at the cap (including a run whose last unit followed an answered ask)
- **THEN** the operation returns a typed outcome carrying the status (`converged` / `non-converged`), the final verdict text, the final ledger snapshot, and the report text, rather than only a verdict string, and an escalation failure raises an error instead of returning an outcome

### Requirement: PR review instruction contract

The pr-review-loop playbook's documentation SHALL declare a three-layer instruction
contract. The **persona** layer is the reviewer instruction: a configured
`reviewInstruction` is a full replacement of the built-in default persona (only a nil
value selects the default; an empty string stays configured as a loud
misconfiguration) and carries no classification duties — the reviewer reviews freely
in prose. The **protocol** layer is a component-owned instruction fragment appended
to every review prompt at runtime and not configurable away: the delta-review rules,
the in-session validation directive, the report-recurrences-by-ledger-id rule, and
family reuse-or-justify guidance. The
**taxonomy** layer is the judge's: what counts as blocking for the repository arrives
through the `blockingAdditions` config field (free text supplied to the judge), not
through the reviewer instruction, so the loop's structure is not sensitive to the
quality or format of a repo-authored instruction.

The playbook's config surface (the exported `Config` type's doc comments for
`reviewInstruction` and `blockingAdditions`) SHALL state each field's layer and role.
The documentation SHALL also state the playbook's boundary: verdicts that do not
reduce to a blocking/non-blocking classification (score gates,
approve/request-changes votes, report-only reviews) are a different playbook, not an
instruction swap, and deterministic signals (CI checks, configured gates) are outside
the playbook — they belong to the calling script.

The documentation SHALL present pointer-style instructions — reviewer instruction text
that references a repository document — as the recommended form when the instruction
is long or repo-pinned, noting that configured text is inlined into every review
prompt.

The playbook SHALL ship a built-in default persona instruction and SHALL use it when
no reviewer instruction is configured; the default carries no classification
directive (classification belongs to the judge).

#### Scenario: Instruction contract is declared

- **WHEN** a consumer consults the pr-review-loop playbook's documentation before supplying a reviewer instruction
- **THEN** the three layers (persona configurable, protocol appended and not configurable away, taxonomy owned by the judge plus `blockingAdditions`) are stated, along with the boundary that verdicts not reducible to a blocking/non-blocking classification belong to a different playbook

#### Scenario: Config surface states the classification requirement

- **WHEN** a consumer reads the exported `Config` type for the pr-review-loop playbook
- **THEN** `reviewInstruction`'s documentation states it is the persona (full replacement; nil selects the built-in default) with no classification duties, and `blockingAdditions`' documentation states it is the judge-facing blocking taxonomy for the repository

#### Scenario: Built-in default instruction used when none is configured

- **WHEN** the playbook is configured without `reviewInstruction` (the field is nil)
- **THEN** reviews run against the playbook's built-in default persona instruction, which carries no blocking/non-blocking classification directive (classification belongs to the judge)

#### Scenario: Configured instruction takes precedence

- **WHEN** `reviewInstruction` is configured with instruction text
- **THEN** the built-in default is not used — the configured text is inlined into the review prompt as the persona, the protocol fragment is still appended, and the judge still supplies the taxonomy regardless of the configured text

#### Scenario: Protocol is not configurable away

- **WHEN** any review pass runs, with a configured persona or the built-in default
- **THEN** the review prompt carries the component-owned protocol fragment (delta rules, in-session validation directive, recurrence-by-ledger-id, family reuse guidance) in addition to the persona

#### Scenario: Pointer pattern is the documented long form

- **WHEN** a consumer consults the pr-review-loop playbook's documentation with a long or repo-pinned reviewer instruction in mind
- **THEN** the documentation presents pointer-style text referencing a repository document as the recommended form

### Requirement: PR review ledger

The pr-review-loop playbook SHALL persist its loop state as a ledger stored in a
dedicated pull-request comment (marked `<!-- ptah:pr-review-ledger -->` and updated in
place through the library's GitHub transport), not in playbook config or local state.
The ledger SHALL carry: the PR identity, the discovery SHA and the `lastReviewedSha`,
the PR's intention (the PR title and body when present; otherwise the last commit
message before the first ledger record, captured at discovery), the findings with
their id, family, severity, validation status, status (`open` / `fixed` / `deferred`
/ `accepted`), and fixing commit where applicable, and the family table. The ledger
SHALL be playbook-owned data; the documentation SHALL state that hand-editing it is
unsupported, that a deleted ledger degrades a fresh run to a new discovery pass
(today's per-run behavior), and that one loop per PR is an environment requirement
(two concurrent loops on one PR corrupt the in-place comment update).

A fresh `review` operation SHALL resume automatically from an existing ledger without
a resume flag: no ledger means a fresh discovery pass; an existing ledger means the
loop continues from its state (open blocking findings → fix turn; a clean ledger at
the current head → converge).

Once a finding's fix has been verified clean in a later review pass, the playbook
SHALL retain it as a terminal one-line entry with status `fixed` — its id, title,
family, and fixing commit — and increment the resolved count, rather than collapsing
it to a bare count, so the PR review report can list what was fixed. A `fixed` entry
no longer participates in reconciliation and never gates convergence. Retaining fixed
entries means the ledger grows with the PR; a ledger that outgrows the platform
comment limit fails loudly through the transport rather than truncating.

#### Scenario: Ledger created at discovery

- **WHEN** the loop's first review pass completes on a PR with no ledger comment
- **THEN** a ledger comment is created carrying the discovery SHA, the last reviewed SHA, the PR's intention, and the typed findings with their families and validation statuses

#### Scenario: Fresh run resumes from the ledger

- **WHEN** a new `review` operation runs against a PR whose ledger comment exists (e.g. after a previous run ended at the cap)
- **THEN** the loop resumes from the ledger's state without a resume flag — open blocking findings drive a fix turn, a clean ledger at the current head converges immediately

#### Scenario: Ledger updated in place after each phase

- **WHEN** a review pass or fix turn completes
- **THEN** the ledger comment is updated in place (never appended as a new comment) reflecting the new `lastReviewedSha`, finding statuses, and family table

#### Scenario: Intention fallback

- **WHEN** the PR has no body at discovery time
- **THEN** the ledger's intention is captured from the last commit message before the first ledger record, and later passes reuse the cached intention

#### Scenario: Resolved findings compact

- **WHEN** a finding's fix has been verified clean in a later review pass
- **THEN** the ledger retains the finding as a terminal one-line entry with status `fixed` (id, title, family, fixing commit) rather than dropping it to a bare count, increments the resolved count, and no longer treats it as open — so the PR review report can list what was fixed

#### Scenario: One loop per PR is a documented requirement

- **WHEN** a consumer consults the playbook's documentation for environment requirements
- **THEN** the one-loop-per-PR requirement is stated alongside the `gh`-based PR-host requirement, and the documentation states the consequence of violating it (concurrent in-place ledger updates corrupting each other)

### Requirement: PR review report

The pr-review-loop playbook SHALL produce a **PR review report** — a human-facing
summary of the whole review — as a pull-request comment marked
`<!-- ptah:pr-review-report -->` and edited in place across runs, for every terminal
outcome of a `review` operation that returns (converged and non-converged). A `review`
operation that fails — an aborted or unservable escalation, or reporter exhaustion —
SHALL NOT produce a report.

The report SHALL be authored by a dedicated reporter agent: a required
`reporterAgent` config handle and an optional `reporterSessionConfig` (applied to
every reporter session in declared order). The reporter SHALL submit a typed result (a
`resultSchema` result) carrying the report body. The playbook SHALL retry a reporter
that submits no typed result a bounded number of times, and exhaustion SHALL fail the
operation with an error naming the reporter and the attempt count — never a silent
absence of the report. The converged work session SHALL NOT author or post the report.

The playbook SHALL post and edit the report through the library's GitHub transport,
matching the ledger's marker-and-edit pattern, so a re-run edits the existing report
rather than appending another. The playbook SHALL prepend a deterministic status line
derived from the ledger — the outcome status and the count of open blocking findings —
so the report's convergence claim is never agent-authored. The reporter SHALL author
the remainder of the body under a playbook-defined section contract.

The report body SHALL cover: the PR's intention; the resolved findings as one-line
entries; the open non-blocking findings; the deferred findings; the accepted findings;
and a loop summary (iterations, discovery and last-reviewed SHAs, and the family
table). For a non-converged outcome the report SHALL lead with an open blocking
findings section beneath the status line. The resolved findings list SHALL be capped
at 50 entries with a note of how many earlier entries are omitted, so the report stays
readable while the ledger retains every entry.

The reporter session SHALL receive the full ledger, the terminal status, and the
required section contract, so the report reflects the whole loop rather than the last
delta alone. It SHALL additionally receive the last review pass's prose when a review
pass ran in the current operation; a resume that converges immediately, or that ends
at the cap without a new review pass, has none, and the report is rendered from the
ledger alone. The ledger is the durable whole-loop source; the prose is supplementary.

#### Scenario: Report produced on convergence

- **WHEN** a review pass converges and the review operation returns
- **THEN** the playbook posts a PR review report whose status line reports convergence and whose body covers the ledger's resolved, open non-blocking, deferred, and accepted findings and the loop summary

#### Scenario: Report produced on cap and leads with blockers

- **WHEN** the loop reaches the cap with open blocking findings and returns a non-converged outcome
- **THEN** the playbook posts a PR review report whose status line reports non-convergence and the open blocking count, and whose body leads with an open blocking findings section

#### Scenario: Report is edited in place across runs

- **WHEN** a `review` operation runs against a PR that already has a report comment
- **THEN** the playbook edits that comment in place rather than appending a second report

#### Scenario: Playbook owns the status line

- **WHEN** the report is produced for any outcome
- **THEN** the status line naming the outcome status and the open blocking count is composed by the playbook from the ledger, not by the reporter

#### Scenario: Reporter exhaustion fails the operation

- **WHEN** the reporter session submits no typed result on every attempt up to the bound
- **THEN** the review operation fails with a script error naming the reporter and the attempt count, and no report is posted

#### Scenario: Reporter receives the full ledger and the last review prose

- **WHEN** the playbook prompts the reporter after a review pass ran in the current operation
- **THEN** the prompt carries the full ledger (including retained `fixed` entries), the terminal status, the last review pass's prose, and the section contract

#### Scenario: Reporter runs without prose on a resume

- **WHEN** a `review` operation returns without running a new review pass — an immediate resume converge, or a resumed ledger already at the cap — and a report is produced
- **THEN** the reporter prompt carries the full ledger, the terminal status, and the section contract with an explicit no-prose marker instead of review prose, and the operation still returns `outcome.report`

#### Scenario: Reporter session config is applied

- **WHEN** the playbook is configured with `reporterSessionConfig` entries and a report is produced
- **THEN** the reporter session receives the entries in declared order before its prompt

#### Scenario: Resolved list is capped

- **WHEN** the ledger holds more than 50 retained `fixed` entries
- **THEN** the report's resolved section lists 50 and notes how many earlier entries are omitted, while the ledger continues to retain every entry

### Requirement: issueWorker meta playbook

The library SHALL provide an `issueWorker` **meta playbook**: a playbook that
composes stdlib helpers, other playbooks, and deterministic stages to take one
GitHub issue from pickup to a reviewed, CI-green pull request. One run
processes at most one issue and leaves nothing running between runs.

The playbook's config SHALL be data plus declared agent handles, and SHALL
NOT contain callable hooks. It SHALL accept the role handles `agent`,
`judgeAgent`, and `reporterAgent`, and the ordered session-config arrays
`sessionConfig`, `judgeSessionConfig`, and `reporterSessionConfig`, following
the library's session-config convention. `agent` and `sessionConfig` SHALL
drive the playbook's own stage sessions and be forwarded as the work agent
handle and work session config to every nested playbook the run drives;
`judgeAgent`/`judgeSessionConfig` SHALL be forwarded to the nested playbooks
that require a judge (the openspec playbook and the PR review loop),
`reporterAgent`/`reporterSessionConfig` to the nested PR review loop, and
`commitSignArgs` to the CI gate.

It SHALL accept the required repo shape `readyLabel` and `blockedLabel` (the
library SHALL ship no default, encoding no repository's label), `baseBranch`,
`branchPrefix`, and `gateCommands`; the defaulted `worktreeDir` (defaulting to
`"tmp"` relative to the repository root, which the consumer is responsible for
gitignoring), `commitTypes` (the conventional-commit vocabulary the triage
verdict's commit type is drawn from), `commitSignArgs`, and caps (`pickupLimit`,
`maxAttempts`, `reviewMaxIterations`, and the CI bounds); an opt-in `openspec`
flag; and an optional `repoBrief` string. `pickupLimit` SHALL bound the candidate issues
inspected while searching for an eligible one — a run still claims and
processes at most one issue; `maxAttempts` SHALL bound the playbook's own
typed-result retries (the triage verdict and the delivery session's
pull-request URL); and `reviewMaxIterations` SHALL be forwarded to the nested
PR review loop's iteration cap.
`repoBrief` SHALL be injected into every playbook-authored stage prompt
(triage, direct implementation, and delivery) so
repository prose (a pointer to `AGENTS.md`, the environment it runs in, a
merge-not-rebase policy) arrives as data while the prompts stay playbook-owned;
its absence SHALL leave the built-in prompts otherwise unchanged.

The instance SHALL expose three operations: `run()`, which performs pickup and,
when an issue is eligible, the whole lifecycle, returning the outcome;
`pickup()`, which returns the claimed issue or nil; and `process(issue)`,
which runs a claimed issue through to delivery or rejection and returns the
outcome. The outcome SHALL be a typed discriminated record with status
`delivered`, `rejected`, `idle`, or `failed`, carrying the issue where one was
claimed (nil on `idle`), the pull request URL where one exists, and a reason on
rejection or failure.

A run SHALL drive the nested PR review loop before the CI gate, and a CI repair
push SHALL NOT re-run the review; when the CI gate returns `unresolved`, or the
nested PR review loop returns a non-converged outcome, the playbook SHALL record
the failure bookkeeping and return a `failed` outcome (carrying the review
verdict for the latter), mirroring each other.
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
- **THEN** it returns an `idle` outcome and performs no issue or pull-request mutation

#### Scenario: A stage failure is recorded, not propagated

- **WHEN** a stage fails after an issue was claimed
- **THEN** the playbook performs the failure bookkeeping and returns a `failed` outcome carrying the reason, and the shim — not the playbook — decides the exit code

#### Scenario: Review precedes the CI gate

- **WHEN** a run delivers a pull request
- **THEN** the nested PR review loop runs before the CI gate, and a CI repair push does not re-run the review

#### Scenario: Unresolved CI fails the run

- **WHEN** the CI gate returns `unresolved`
- **THEN** the playbook records the failure bookkeeping and returns a `failed` outcome

#### Scenario: Non-converged review fails the run

- **WHEN** the nested PR review loop returns a non-converged outcome
- **THEN** the playbook records the failure bookkeeping and returns a `failed` outcome carrying the review verdict, and the CI gate is not run

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

- **WHEN** another run assigns itself between the eligibility read and this run's claim, so the re-read of the assignee set finds anything other than exactly the authenticated user
- **THEN** the playbook removes its own assignment, skips that issue, and continues with the next candidate

#### Scenario: Labels are created idempotently

- **WHEN** the ready or blocked label does not exist in the repository
- **THEN** the playbook creates it, and an existing label is left as is

### Requirement: Triage routes and planning

The playbook SHALL run one triage session in the issue worktree that returns a
typed verdict through the session's result: a route, a rationale, a
conventional-commit type, and — on the openspec route — a change name. A
verdict that is missing or invalid SHALL be retried a bounded number of times,
and exhaustion SHALL record the failure bookkeeping and return a `failed`
outcome. The route SHALL be `direct` or `reject`, and additionally `openspec`
only when the openspec opt-in is enabled. On the openspec route the playbook
SHALL require that the named change directory exists before driving the
openspec playbook's groom, implement, and verify operations, and SHALL record
the failure bookkeeping and return a `failed` outcome if it does not. On the direct route one
session SHALL implement the issue in the worktree and commit the work with the
configured signing arguments. On the reject route the playbook SHALL perform
the blocked bookkeeping and return a `rejected` outcome without delivering.

#### Scenario: Invalid verdict is retried

- **WHEN** the triage session submits no typed result, or a result missing a route, rationale, or commit type
- **THEN** the playbook re-prompts up to the retry bound and returns a `failed` outcome if no valid verdict arrives

#### Scenario: Direct route implements and commits

- **WHEN** triage returns the direct route
- **THEN** one session implements the issue in the worktree and commits with the configured signing arguments, and no pull request is opened by that session

#### Scenario: Reject route blocks without delivering

- **WHEN** triage returns the reject route
- **THEN** the playbook records the rationale as blocked bookkeeping and returns a `rejected` outcome

#### Scenario: openspec route requires its change

- **WHEN** triage returns the openspec route with a change name but the change directory does not exist in the worktree
- **THEN** the playbook records the failure bookkeeping and returns a `failed` outcome naming the missing change

#### Scenario: openspec route drives the openspec playbook

- **WHEN** triage returns the openspec route and the change exists
- **THEN** the playbook runs the openspec playbook's groom, implement, and verify operations for that change, in order, in the worktree

### Requirement: Delivery contract

The playbook SHALL deliver the issue branch through one session that runs the
configured gate commands, brings the branch up to date with the base branch by
merging — never rebasing, so signed commits are preserved — pushes the branch,
and opens a pull request against the base branch whose body begins with the
issue's closing reference and whose title is the triage verdict's
conventional-commit type (drawn from the configured `commitTypes`) composed
with the issue title. The session SHALL
submit the pull request URL as a typed result, retried a bounded number of
times. Before the pull request is handed onward, the playbook SHALL
deterministically re-check that the branch has at least one commit ahead of
the base branch, that the reported URL is a pull URL, and that the pull
request's title matches the composed title — correcting the title through the
transport and returning a `failed` outcome if it cannot be corrected.

#### Scenario: Delivery re-checks are deterministic

- **WHEN** the delivery session reports a pull request URL
- **THEN** the playbook re-checks commits-ahead, the URL shape, and the title itself rather than trusting the session's prose

#### Scenario: Branch with no commits ahead fails delivery

- **WHEN** the delivered branch has no commits ahead of the base branch
- **THEN** the playbook records the failure bookkeeping and returns a `failed` outcome naming the branch

#### Scenario: Title is corrected or fails

- **WHEN** the opened pull request's title differs from the composed conventional-commit title
- **THEN** the playbook edits the title and returns a `failed` outcome if it still does not match

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
repair push committed with the configured signing arguments. It SHALL classify
each rollup entry across the check-run
and status-context shapes and SHALL proceed only when every entry is
successful, neutral, or skipped. The playbook SHALL accept an `agent` handle,
an ordered `sessionConfig` array, the commit-signing arguments applied to a
repair commit, a wait budget, a poll interval, and a
repair-attempt cap. It SHALL NOT accept a `cwd`: repair sessions run in the
working directory of the supplied `agent` handle, so a consumer running outside
a worktree pins the handle (e.g. `std.agent.inDirectory`) before constructing
the playbook. Its `watch` operation SHALL take the pull request URL and return a typed
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
- **THEN** the playbook hands the failing logs to the agent for a repair push committed with the configured signing arguments and re-watches the rollup

#### Scenario: Repair runs in the handle's directory

- **WHEN** a repair push is issued
- **THEN** the repair session runs in the working directory of the supplied `agent` handle

#### Scenario: Repair budget exhausted

- **WHEN** checks remain red after the configured repair attempts
- **THEN** `watch` returns an `unresolved` outcome carrying the attempt count rather than raising

#### Scenario: Wait budget exhausted

- **WHEN** checks have not reached a terminal state within the wait budget
- **THEN** `watch` returns an `unresolved` outcome naming the timeout rather than raising

#### Scenario: Status contexts and check runs are both classified

- **WHEN** the check rollup mixes check-run entries and status-context entries
- **THEN** each entry's conclusion, state, and status are classified so pending entries do not read as failures

### Requirement: Offline test coverage

Every stdlib module and playbook entry point SHALL be exercised by an
offline test suite against the mock agent, with no network access and no
real agent. The suite is maintained in the ptah repository (this repository
ships no test suite); this requirement is the library's contract that such
coverage exists.

#### Scenario: Library regressions caught offline

- **WHEN** a library module's behavior breaks (e.g. the judge stops returning verdicts)
- **THEN** the offline suite fails without spawning any real agent
