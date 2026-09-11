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
`std` (with `predicate`, `gh`, `daemon`, `sessionConfig`, and `escalate`),
`openspec`, and `prReviewLoop`. Deep-path requires into the library tree
SHALL NOT be part of the supported consumer surface.

#### Scenario: Consumer installs as a git dependency

- **WHEN** a consumer declares a pesde git dependency on this repository at a tag revision and runs `pesde install`
- **THEN** pesde's generated `luau_packages` shim requires the package entry and re-exports its values and types, and the consumer's shim reaches the library through that generated shim

#### Scenario: Entry exports the library surface

- **WHEN** a consumer requires the generated dependency shim
- **THEN** `std.predicate`, `std.gh`, `std.daemon`, `std.sessionConfig`, `std.escalate`, `openspec`, and `prReviewLoop` are available on the returned table

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

#### Scenario: Ask carries identity, session label, and full probe text

- **WHEN** the playbook raises an escalation ask
- **THEN** the prompt line identifies the operation, the change, and the iteration state, and the details carry the work session's label and the full probe text without truncation

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

The library SHALL provide a PR review loop playbook that runs a
review→fix→push convergence against a pull request, with repository-specific
settings (agent prompts, reviewer instruction text, dry-run gating)
expressed as config rather than code. The target repository SHALL NOT be
playbook config: it arrives per call inside the PR URL.

On a confirmed need for human input (the escalation judge confirms the
blocking findings need a human), the loop SHALL ask through the library's
escalation mechanism with an ask whose prompt line identifies the loop and
the PR URL and the iteration state, and whose details carry the work
session's label and the full probe text. When the ask is answered, the
answer text SHALL be sent verbatim as the next prompt of the still-open
work session (no header or framing added), the commit-and-push step SHALL
still follow the human-guided fix (gated by dry-run as any fix), the
iteration SHALL count against the cap, and the loop SHALL continue toward
convergence. When the human aborts the ask, the operation SHALL fail with
a distinct error stating the human aborted the escalation. When no ask
provider serves the request, the operation SHALL fail with an error
stating human input is needed to resolve the findings — the same wording
as before the ask existed.

The playbook's config SHALL accept `sessionConfig`, an ordered
session-config entry array applied to every work session the playbook
creates (each review/fix iteration's session, which also posts the verdict
comment), and `judgeSessionConfig`, applied to every judge and
human-escalation-probe session. The `model` and `judgeModel` config
fields SHALL NOT exist: a model choice is an ordinary `sessionConfig`
entry, and the entry order is the consumer's `setConfig` order.

#### Scenario: Review finds fixable findings

- **WHEN** the reviewer reports findings judged resolvable without a human
- **THEN** the playbook drives a fix session and pushes, iterating until the review passes or escalation occurs

#### Scenario: Human escalation asks and resumes

- **WHEN** the reviewer's blocking findings are judged to need human input, an ask provider serves the request, and the human answers
- **THEN** the answer is sent verbatim as the next prompt of the still-open work session, the commit-and-push step follows the human-guided fix (gated by dry-run as any fix), the iteration counts against the cap, and the loop continues toward convergence

#### Scenario: Human escalation abort fails

- **WHEN** the reviewer's blocking findings are judged to need human input, an ask provider serves the request, and the human aborts the ask
- **THEN** the operation fails with a distinct error stating the human aborted the escalation, and no fix is issued

#### Scenario: Unservable ask fails as before

- **WHEN** the reviewer's blocking findings are judged to need human input and no ask provider serves the request
- **THEN** the operation fails with an error stating human input is needed to resolve the findings — the same wording as before the ask existed — and no fix is issued

#### Scenario: Ask carries identity, session label, and full probe text

- **WHEN** the loop raises an escalation ask
- **THEN** the prompt line identifies the loop, the PR URL, and the iteration state, and the details carry the work session's label and the full probe text without truncation

#### Scenario: Repository context is per-call

- **WHEN** the loop reviews a pull request
- **THEN** the repository context comes from the PR URL passed to the operation, and the playbook's config declares no repository field

#### Scenario: Work sessions receive session config

- **WHEN** the playbook is configured with `sessionConfig` entries and the review loop runs
- **THEN** every per-iteration work session receives the entries in declared order before its first prompt

#### Scenario: Judge and probe sessions receive judge session config

- **WHEN** the playbook is configured with `judgeSessionConfig` entries and the review loop runs
- **THEN** every judge session and every human-escalation-probe session receives the entries in declared order before its prompt

#### Scenario: Removed model field is a type error

- **WHEN** a consumer shim configures the removed `model` or `judgeModel` field and runs `ptah check`
- **THEN** check reports a type error naming the unknown field, steering the consumer to the `sessionConfig` entry form

### Requirement: PR review instruction contract

The pr-review-loop playbook's documentation SHALL declare the contract its
reviewer instruction must satisfy: a configured reviewer instruction defines
what counts as a blocking issue for the repository and instructs the
reviewer to classify findings as blocking or non-blocking, and the
playbook's judge predicates and fix prompts speak that classification
vocabulary. The playbook's config surface (the exported `Config` type's
doc comment for `reviewInstruction`) SHALL state the classification
requirement. The documentation SHALL also state the playbook's boundary:
verdicts that do not reduce to a blocking/non-blocking classification
(score gates, approve/request-changes, report-only reviews) are a different
playbook, not an instruction swap.

The documentation SHALL present pointer-style instructions — reviewer
instruction text that references a repository document — as the recommended
form when the instruction is long or repo-pinned, noting that configured
text is inlined into every iteration's review prompt.

The playbook SHALL ship a built-in default instruction that satisfies this
contract and SHALL use it when no reviewer instruction is configured; a
configured reviewer instruction SHALL take precedence over the built-in
default, as a full replacement (the configured text is the entire
instruction, inlined into the review prompt). Only a nil `reviewInstruction`
selects the built-in default.

#### Scenario: Instruction contract is declared

- **WHEN** a consumer consults the pr-review-loop playbook's documentation before supplying a reviewer instruction
- **THEN** the required blocking/non-blocking verdict classification is stated, along with the boundary that verdicts not reducible to it belong to a different playbook

#### Scenario: Config surface states the classification requirement

- **WHEN** a consumer reads the exported `Config` type for the pr-review-loop playbook
- **THEN** the `reviewInstruction` field's documentation states that a configured reviewer instruction must classify findings as blocking or non-blocking, and that a nil value selects the built-in default

#### Scenario: Built-in default instruction used when none is configured

- **WHEN** the playbook is configured without `reviewInstruction` (the field is nil)
- **THEN** reviews run against the playbook's built-in default instruction, which directs the reviewer to classify each finding as blocking or non-blocking (the default is the contract's reference instance)

#### Scenario: Configured instruction takes precedence

- **WHEN** `reviewInstruction` is configured with instruction text
- **THEN** the built-in default is not used — the configured text is inlined into the review prompt, the default's classification directive is absent, and the configured instruction governs the review

#### Scenario: Pointer pattern is the documented long form

- **WHEN** a consumer consults the pr-review-loop playbook's documentation with a long or repo-pinned reviewer instruction in mind
- **THEN** the documentation presents pointer-style text referencing a repository document as the recommended form

### Requirement: Offline test coverage

Every stdlib module and playbook entry point SHALL be exercised by an
offline test suite against the mock agent, with no network access and no
real agent. The suite is maintained in the ptah repository (this repository
ships no test suite); this requirement is the library's contract that such
coverage exists.

#### Scenario: Library regressions caught offline

- **WHEN** a library module's behavior breaks (e.g. the judge stops returning verdicts)
- **THEN** the offline suite fails without spawning any real agent
