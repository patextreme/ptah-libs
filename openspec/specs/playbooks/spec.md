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
`std` (with `predicate`, `gh`, `daemon`, `sessionConfig`, `escalate`, and
`worktree`), `openspec`, `pr`, and `issue`. Top-level playbook exports are named for the entity
they manage; deep-path requires into the library tree SHALL NOT be part of
the supported consumer surface.

#### Scenario: Consumer installs as a git dependency

- **WHEN** a consumer declares a pesde git dependency on this repository at a tag revision and runs `pesde install`
- **THEN** pesde's generated `luau_packages` shim requires the package entry and re-exports its values and types, and the consumer's shim reaches the library through that generated shim

#### Scenario: Entry exports the library surface

- **WHEN** a consumer requires the generated dependency shim
- **THEN** `std.predicate`, `std.gh`, `std.daemon`, `std.sessionConfig`, `std.escalate`, `std.worktree`, `openspec`, `pr`, and `issue` are available on the returned table

#### Scenario: The renamed export replaces the former name

- **WHEN** a consumer requires the generated dependency shim
- **THEN** `prReviewLoop` is not available on the returned table (the rename is a clean break; consumers pin the prior tag to defer it)

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
an agent handle, a session id, a retry bound, an optional ordered array
of session-config entries applied to every judge attempt session before
its prompt, and an optional working directory applied to every judge
attempt session (so a caller running a loop inside a working directory
can keep its judge sessions there too); no dedicated model field SHALL
exist (a model choice is an ordinary session-config entry). A judge that submits no verdict SHALL be
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

#### Scenario: Judge sessions run in the configured directory

- **WHEN** the judge is invoked with a working directory
- **THEN** every attempt session runs in that directory, and a judge invoked without one keeps today's behavior

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

### Requirement: Worktree lifecycle

The library SHALL provide a worktree lifecycle mechanism (`std.worktree`)
that provisions and tears down git linked worktrees through ptah's exec,
so consumer shims isolate per-item runs in their own worktree without
managing git state by hand. The mechanism SHALL accept no agent handles
and no configuration table: `git` on PATH is a declared environment
requirement, like the GitHub transport's `gh`.

`provision` SHALL accept a required `name`, a required `ref` (no default —
never the shared tree's HEAD, so a worktree is never silently based on
whatever the shared checkout happens to sit on), an optional `branch`
(defaulting to the ref's short name for remote-tracking refs), an
optional `fetch`, an optional `repo` (defaulting to the repository of the
invocation directory), and an optional `parent` (defaulting to the
repository root's sibling directory, so worktrees never live inside a
checkout of the repository). An explicit relative `parent` SHALL resolve
against the selected repository root, not the invocation directory. It
SHALL derive the worktree target as
`<parent>/<repo-basename>-<name>`, resolve that target to the same
canonical physical absolute path Git uses for registration, and return a
record carrying that path, the branch, and the ref. The one canonical
path SHALL be used for inventory lookup, existence checks, Git
operations, diagnostics, and the returned record; after creation, Git's
registered path SHALL be authoritative. Worktree inventory processing
SHALL preserve every valid path exactly, including paths containing
spaces, non-ASCII characters, quoting characters, and line delimiters.
When `fetch` is set, provision SHALL fetch the ref's remote (a plain
fetch, no refspec) before resolution.

Provision SHALL resolve in this order, and SHALL never reset an adopted
worktree or branch — a crashed run's unpushed commits are never silently
destroyed:

- a registered worktree at the path is **adopted as-is** (its branch must
  match; a mismatch, or an unregistered directory at the path, raises);
- otherwise, when the local branch exists and `ref` is its remote-tracking
  counterpart, the branch is **fast-forwarded-or-failed** via
  `git fetch <remote> <branch>:<branch>` — a no-op when current, a
  fast-forward when behind, a loud error when diverged (unpushed commits
  and a moved origin is a human decision, not an automatic one) — and the
  worktree is attached to the branch;
- otherwise, when the local branch exists and `ref` is anything else (the
  resume case: the worktree was torn down but the branch survived), the
  worktree is attached to the existing branch **as-is**;
- otherwise the branch is created from the ref (`git worktree add -b
  <branch> <path> <ref>`), with git's upstream auto-set applying for a
  remote-tracking ref — so a plain `git push` from inside the worktree
  pushes the intended branch.

Provision SHALL never rename or prefix branches (an aliased branch name
would make a naive `git push` push the wrong branch), and a failed git
command SHALL raise carrying git's stderr (pcall-able) — there is no
outcome-object form, because a failed provision means the run cannot
proceed.

`teardown` SHALL accept the provision record (any record carrying `path`)
and an optional `force`. It SHALL refuse a dirty worktree by default,
remove and prune otherwise, and SHALL NOT touch branches: unpushed
commits survive on the local branch, and no branch-deletion operation
exists in the mechanism. Teardown SHALL return its outcome as data (`ok`,
and `stderr` on failure) rather than raising — a dirty refusal after a
converged loop is something the caller logs, not a failed run.

#### Scenario: Fresh provision creates a pushable branch

- **WHEN** provision runs with no existing worktree at the path and no local branch
- **THEN** the branch is created from the ref with upstream auto-set for a remote-tracking ref, and a plain `git push` from inside the worktree pushes the intended branch

#### Scenario: Ref is required

- **WHEN** provision is called without a `ref`
- **THEN** it raises; there is no default start point, and never the shared tree's HEAD

#### Scenario: Existing worktree is adopted as-is

- **WHEN** provision runs and a registered worktree exists at the derived path on the requested branch
- **THEN** the existing worktree is returned unchanged — no reset, no re-add — so an interrupted run resumes

#### Scenario: Relative parent resolves from the repository root

- **WHEN** provision receives a relative `parent`, including when invoked from a subdirectory of the selected repository
- **THEN** it resolves the parent against the selected repository root and returns the canonical physical absolute worktree path

#### Scenario: Relative-parent rerun adopts the original worktree

- **WHEN** provision is called twice with the same relative `parent`, name, ref, and branch
- **THEN** the second call identifies and adopts the worktree created by the first call without resetting it or changing its status

#### Scenario: Symlinked parent uses Git's physical path

- **WHEN** an explicit parent reaches an existing directory through a symbolic-link alias
- **THEN** provision compares, operates on, logs, and returns the physical absolute path Git records, so a rerun through the alias adopts the same worktree

#### Scenario: Unusual valid paths survive inventory parsing

- **WHEN** a registered worktree path contains spaces, non-ASCII characters, quoting characters, or line delimiters
- **THEN** provision preserves the path exactly and can identify and adopt that worktree

#### Scenario: Dirty worktree is adopted unchanged

- **WHEN** the registered worktree is on the requested branch and contains uncommitted or untracked changes
- **THEN** provision adopts it without resetting, cleaning, stashing, switching, or otherwise changing its status

#### Scenario: Branch mismatch at the path errors

- **WHEN** the registered worktree at the path is on a different branch or detached, or an unregistered directory sits at the path
- **THEN** provision raises and leaves the worktree or directory untouched; adoption never silently switches or discards

#### Scenario: Existing branch fast-forwards against its remote counterpart

- **WHEN** the local branch exists, `ref` is its remote-tracking counterpart, and the branch is behind the remote
- **THEN** the branch is fast-forwarded before the worktree is attached — a no-op when current, never a rebase or reset

#### Scenario: Diverged branch errors loudly

- **WHEN** the local branch has unpushed commits and its remote counterpart has moved
- **THEN** provision raises; reconciling diverged work is a human decision

#### Scenario: Resume case attaches to the surviving branch

- **WHEN** the local branch exists (a previous teardown kept it) and `ref` is that branch
- **THEN** the worktree is attached to the existing branch as-is, preserving its commits

#### Scenario: Path derivation stays outside the repository

- **WHEN** `parent` is omitted
- **THEN** the worktree path is `<sibling-of-the-repo-root>/<repo-basename>-<name>`, canonical and absolute, never inside a checkout of the repository

#### Scenario: Provision failure raises with stderr

- **WHEN** any git command provision runs fails
- **THEN** provision raises an error carrying git's stderr; no outcome-object form exists

#### Scenario: Clean teardown removes and prunes

- **WHEN** teardown runs on a clean worktree
- **THEN** the worktree is removed and pruned, and the outcome reports success

#### Scenario: Dirty refusal is data, not an error

- **WHEN** teardown runs on a worktree with uncommitted or untracked files and no `force`
- **THEN** teardown returns a failed outcome carrying git's message and raises nothing; the worktree is left in place

#### Scenario: Force overrides the dirty refusal

- **WHEN** teardown runs with `force` on a dirty worktree
- **THEN** the worktree is removed and pruned, discarding the uncommitted changes

#### Scenario: Branches survive teardown

- **WHEN** teardown succeeds on a worktree whose branch has unpushed commits
- **THEN** the local branch and its commits remain — teardown never deletes branches

### Requirement: Playbook working directory

The `openspec` and `pr` playbooks' config SHALL accept an optional
`workingDir`: when set, **every** session the playbook creates — work
sessions, judge sessions, human-escalation-probe sessions, the archive
session, reporter sessions — SHALL run in that directory (ptah's
per-session working directory), so no session of the playbook can read
or write the wrong tree. When `workingDir` is nil, behavior SHALL be
byte-for-byte today's: sessions run in the invocation directory. The
field SHALL be documented as an absolute path.

The playbooks SHALL remain git-agnostic: their config declares no
worktree fields, and provisioning or tearing down a worktree is the
calling shim's business (the worktree lifecycle mechanism is one producer
of working directories; a plain clone is another).

#### Scenario: Every session runs in the working directory

- **WHEN** either playbook is configured with `workingDir` and any operation runs
- **THEN** every session the playbook creates — work, judge, probe, archive, reporter alike — runs in that directory

#### Scenario: Omitted working directory is unchanged

- **WHEN** either playbook is configured without `workingDir`
- **THEN** every session runs in the invocation directory, exactly as before the field existed

#### Scenario: Playbooks never manage worktrees

- **WHEN** a consumer consults either playbook's exported config type
- **THEN** no field provisions, adopts, or tears down a worktree — lifecycle verbs belong to the worktree mechanism, called by the shim

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
review prose, the ledger state (open and deferred findings with their ids), the PR's
intention, and the configured `blockingAdditions` text, and SHALL return typed findings
carrying per-finding severity (blocking or non-blocking), a family name, a validation
status, and the judge's `needsHuman` determination, together with a reconciliation of
the ledger's findings — resolved (with evidence), still open, or still deferred —
covering both open and deferred entries. The judge SHALL steer findings against the
PR's intention: a finding the judge rates important but outside the PR's scope SHALL
be recorded with a deferred status in the ledger, SHALL NOT gate convergence, and
SHALL be surfaced in the PR review report's deferred list. A recurrence of a deferred
finding SHALL be reported against that finding's id as still deferred, never refiled
as a new finding. A judge that submits no typed result SHALL be retried a bounded
number of times, and exhaustion SHALL fail the iteration — never a silent converge.
The judge agent is a required config handle: the loop's convergence depends on it,
and no prose-parsing fallback replaces it.

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

The loop's only escalation trigger is the judge's `needsHuman` flag on a finding that
gates convergence: the loop SHALL ask only when an open, blocking finding carries
`needsHuman`, whether raised as a new finding or through a reconciliation record. A
reconciliation record SHALL trigger the ask only when the ledger finding it names by
id is itself open and blocking; a record naming an id absent from the ledger SHALL
never trigger an ask. The `needsHuman` flag on a non-blocking or deferred finding
SHALL NOT trigger an ask: the concern surfaces in the review prose and the posted
report, with the flag persisted in the ledger.

When the trigger fires, the loop SHALL ask through the library's escalation mechanism
with an ask whose prompt line identifies the loop, the PR URL, and the iteration
state, and names every triggering finding (id, family, severity, title); the details
SHALL carry the answer grammar the loop understands (`defer <id>`,
`accept <id>`, `fix: <instructions>`), the work session's label, the agent-side ACP
session id, and the full review prose without truncation.

When the ask is answered, the answer SHALL be adjudicated before any fix turn: a
typed adjudication session — the judge agent under a dedicated result schema —
receives the verbatim answer, the triggering findings, and the ledger, and returns
per-finding mutations: `defer` (the finding transitions open → deferred) and `accept`
(open → accepted), each with an optional note, and `fix` (the finding stays open and
the answer directs its fix). Mutations SHALL target existing open findings only: ids
that are unknown or already terminal are no-ops, and adjudication SHALL NOT create
findings. The contract SHALL be one decision per finding: when the adjudication names
a finding id more than once, only its last mutation SHALL apply, so an applied `fix`
mutation always leaves its finding open and a pushed fix turn is always followed by a
review pass. The ask's prompt line, the verbatim answer, and the applied mutations SHALL
be recorded in the ledger's decisions record, and a decided finding's persisted
`needsHuman` flag SHALL be cleared. When the adjudication includes at least one `fix`
mutation, the answer text SHALL be sent verbatim as the next prompt of the
still-open work session (no header or framing added), and the commit-and-push step
SHALL follow (gated by dry-run as any fix). A decision-only answer (no `fix`
mutation) SHALL issue no work-session prompt and no commit-and-push. The iteration
SHALL count against the cap either way, and the loop SHALL continue toward
convergence; when a decision-only adjudication leaves no open blocking findings, the
loop SHALL converge immediately without a further review pass. When the human aborts
the ask, the operation SHALL fail with a distinct error stating the human aborted
the escalation. When no ask provider serves the request, the operation SHALL fail
with an error stating human input is needed to resolve the findings. An adjudication
session that submits no typed result SHALL be retried a bounded number of times, and
exhaustion SHALL fail the iteration — never a silent mutation.

The playbook's config SHALL accept `agent` and the required `judgeAgent` and
`reporterAgent` handles, `sessionConfig` (applied to every work session the playbook
creates), `judgeSessionConfig` (applied to every judge session and every adjudication
session), `reporterSessionConfig` (applied to every reporter session),
`reviewInstruction` (persona, per the instruction contract), `blockingAdditions`
(free text supplied to the judge defining what counts as blocking for the
repository), `dryRun`, and `maxIterations` (default 8). The `model` and `judgeModel`
config fields SHALL NOT exist: a model choice is an ordinary `sessionConfig` entry,
and the entry order is the consumer's `setConfig` order.

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
- **THEN** a typed judge session receives the prose, the ledger's open and deferred findings with their ids, the PR intention, and the configured `blockingAdditions`, and returns structured findings (severity, family, validation status, `needsHuman`) plus a reconciliation of those findings (resolved with evidence, still open, or still deferred)

#### Scenario: Convergence is computed from typed findings

- **WHEN** the judge's typed output reports no open blocking findings
- **THEN** the loop converges and the playbook produces a PR review report whose status line reports convergence

#### Scenario: Review finds fixable findings

- **WHEN** the judge's typed output reports open blocking findings and budget remains, and the judge flags `needsHuman` on no open blocking finding
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
- **THEN** the finding is recorded with a deferred status, the loop may converge with it open, the PR review report lists it under deferred findings, and it does not trigger an ask even when it carries `needsHuman`

#### Scenario: Deferred recurrence reconciles by id

- **WHEN** a later review pass flags a concern matching a deferred ledger finding
- **THEN** the judge's reconciliation reports it against the existing finding's id as still deferred, and the ledger records no duplicate entry for the same concern

#### Scenario: Non-blocking needsHuman does not ask

- **WHEN** the judge flags `needsHuman` on a non-blocking or deferred finding and open blocking findings exist
- **THEN** no ask is raised; the loop issues the batched fix turn for the open blocking findings, and the flagged concern's `needsHuman` determination is persisted in the ledger and rendered in the PR review report

#### Scenario: Unknown reconciliation id never escalates

- **WHEN** a reconciliation record flags `needsHuman` naming an id that matches no ledger finding
- **THEN** the record does not trigger an ask, and the loop proceeds by its convergence state alone

#### Scenario: Answer is adjudicated before any fix turn

- **WHEN** an ask is answered
- **THEN** a typed adjudication session returns per-finding mutations derived from the verbatim answer and the ledger, and the mutations are applied to the ledger before any work-session prompt is issued

#### Scenario: Human decision reaches the ledger

- **WHEN** the judge flags `needsHuman` on an open blocking finding and the ask is answered with a deferral for that finding
- **THEN** adjudication transitions the finding to deferred with the decision note, clears its `needsHuman` flag, records the ask's prompt line, the verbatim answer, and the mutations in the ledger's decisions record, issues no work-session prompt and no commit-and-push, and the loop does not re-ask the same finding

#### Scenario: Human escalation asks and resumes

- **WHEN** the judge flags `needsHuman` on an open blocking finding, an ask provider serves the request, and the human answers
- **THEN** the answer is adjudicated into typed ledger mutations before any fix turn; when the adjudication includes a `fix` mutation, the answer is sent verbatim as the next prompt of the still-open work session and the commit-and-push step follows (gated by dry-run as any fix); the iteration counts against the cap, and the loop continues toward convergence

#### Scenario: Decision-only adjudication converges immediately

- **WHEN** an adjudication applies only defer or accept mutations and leaves no open blocking findings
- **THEN** the loop converges without a further review pass, and the PR review report annotates the decided findings as maintainer decisions

#### Scenario: Adjudication mutations are inert on unknown or terminal ids

- **WHEN** the adjudication output names a finding id that is unknown or already terminal
- **THEN** no mutation is applied for that id and the loop proceeds

#### Scenario: Duplicate adjudication ids keep the last decision

- **WHEN** the adjudication returns more than one mutation for the same finding id
- **THEN** only the last mutation for that id is applied and recorded, and a `fix` for a finding the same batch defers or accepts issues no fix turn and no push

#### Scenario: Adjudication exhaustion fails the iteration

- **WHEN** the adjudication session submits no typed result on every attempt up to the bound
- **THEN** the iteration fails with a script error naming the adjudication session and the attempt count, and no ledger mutation is applied

#### Scenario: Ask carries identity, session label, ACP session id, and full probe text

- **WHEN** the loop raises an escalation ask
- **THEN** the prompt line identifies the loop, the PR URL, and the iteration state and names every triggering finding (id, family, severity, title), and the details carry the answer grammar (`defer <id>`, `accept <id>`, `fix: <instructions>`), the work session's label, the agent-side ACP session id, and the full review prose (the probe payload in this design) without truncation

#### Scenario: Human escalation abort fails

- **WHEN** the judge flags `needsHuman` on an open blocking finding, an ask provider serves the request, and the human aborts the ask
- **THEN** the operation fails with a distinct error stating the human aborted the escalation, and no fix is issued

#### Scenario: Unservable ask fails as before

- **WHEN** the judge flags `needsHuman` on an open blocking finding and no ask provider serves the request
- **THEN** the operation fails with an error stating human input is needed to resolve the findings — the same wording as before the ask existed — and no fix is issued

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
- **THEN** every judge session and every adjudication session receives the entries in declared order before its prompt

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
their id, family, severity, validation status, the judge's `needsHuman` determination,
status (`open` / `fixed` / `deferred` / `accepted`), and fixing commit where
applicable, the family table, and a decisions record. The decisions record SHALL
carry, for every answered ask in ask order (no timestamps), the ask's prompt line, the
verbatim answer, and the applied per-finding mutations with their notes. The ledger
SHALL be playbook-owned data; the documentation SHALL state that hand-editing it is
unsupported, that a deleted ledger degrades a fresh run to a new discovery pass
(today's per-run behavior), and that one loop per PR is an environment requirement
(two concurrent loops on one PR corrupt the in-place comment update).

A finding's `needsHuman` flag SHALL be recorded when the finding is filed, SHALL be
updated whenever a later reconciliation revisits the finding (the judge's latest
determination wins), and SHALL be cleared when an adjudicated decision records a
mutation for the finding (the human's determination supersedes the judge's). A ledger
written before the flag existed SHALL be read tolerantly: a finding without the field
is treated as not needing a human, and the field is written on the next persist.

Finding status SHALL be written by the reconciliation path (open → fixed when a fix
is verified clean) and the adjudication path (open → deferred, open → accepted, by
recorded human decision). Deferred and accepted are terminal: they have no exit
transitions, and a deferred concern that becomes in-scope again is filed as a new
open finding.

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
- **THEN** a ledger comment is created carrying the discovery SHA, the last reviewed SHA, the PR's intention, and the typed findings with their families, validation statuses, and `needsHuman` determinations

#### Scenario: needsHuman flag persists, updates, and clears

- **WHEN** a finding is filed with `needsHuman` flagged, a later reconciliation revisits the finding, and an adjudicated decision records a mutation for it
- **THEN** the ledger carries the judge's latest determination until the decision lands, then shows the flag cleared, and the PR review report renders the flag on undecided findings' lines and the maintainer-decision annotation on decided ones

#### Scenario: Decisions recorded on answered asks

- **WHEN** an ask is answered and adjudicated
- **THEN** the ledger's decisions record gains an entry carrying the ask's prompt line, the verbatim answer, and the applied mutations with their notes, ordered by ask with no timestamps

#### Scenario: Legacy ledgers read tolerantly

- **WHEN** the loop reads a ledger written before the `needsHuman` field and the decisions record existed
- **THEN** findings parse without the field and are treated as not needing a human, no decisions are assumed, and both are written on the next persist

#### Scenario: Fresh run resumes from the ledger

- **WHEN** a new `review` operation runs against a PR whose ledger comment exists (e.g. after a previous run ended at the cap)
- **THEN** the loop resumes from the ledger's state without a resume flag — open blocking findings drive a fix turn, a clean ledger at the current head converges immediately

#### Scenario: Ledger updated in place after each phase

- **WHEN** a review pass or fix turn completes
- **THEN** the ledger comment is updated in place (never appended as a new comment) reflecting the new `lastReviewedSha`, finding statuses, `needsHuman` flags, decisions, and family table

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

### Requirement: Issue pickup playbook

The library SHALL provide an issue pickup playbook that scans a
repo-configured queue label and claims one eligible issue for the calling
script to work. The queue label SHALL be a required config value with no
default: the label vocabulary is the repository's, never the playbook's.
The playbook SHALL NOT configure agents, judges, session-config entries,
or asks — pickup is pure GitHub CLI transport (the `gh` CLI on the
agent's PATH with credentials is a declared environment requirement, and
the token SHALL have permission to edit assignees — triage access or
higher — in the target repository, likewise declared).

Eligibility SHALL consider exactly three signals: the queue label is
present, the issue is not foreign-assigned, and the issue carries no
claim marker comment. The account SHALL be the authenticated identity
itself — no config field — so the foreign-assignment check and the claim
share one identity. "Foreign-assigned" means the issue has assignees and
none of them is the authenticated account: an unassigned issue is
eligible, an issue whose assignees include the account is eligible
(whether or not a teammate is cc'd alongside it), and only an issue
assigned exclusively to other accounts is ineligible. No triage verdict
or other signal SHALL affect eligibility. The scan SHALL consider every
labeled issue — the whole labeled queue, not only a fixed-size first
page, and regardless of queue size — and the playbook SHALL order
eligible issues oldest-first by issue number, deterministically. The
scan SHALL NOT narrow candidates server-side by assignee (the issues
endpoint takes a single `assignee` term and cannot express "none or
mine" as a union); the client-side foreign-assignment check SHALL be the
only assignment signal.

The `pickUp` operation SHALL accept either no argument (scan and claim
the oldest eligible issue) or an issue number (claim that issue only if
eligible). The operation SHALL return a typed outcome discriminated on
`status`: `claimed` carrying the pickup brief, or `no-eligible-issue`
carrying the scan summary (the count of issues examined under the full
eligibility scope — labeled and not foreign-assigned). A scan that finds
no eligible issue SHALL return the `no-eligible-issue` outcome rather
than raising.

When no eligible issue exists for a requested issue number, the operation
SHALL raise an error stating the reason (missing queue label, assigned
to another account, or already claimed).

#### Scenario: Consumer configures the queue label

- **WHEN** a consumer constructs the issue playbook without a queue label and runs `ptah check`
- **THEN** check reports a type or validation error naming the missing required field, and no default label is ever assumed

#### Scenario: Oldest eligible issue is picked up

- **WHEN** `pickUp` is called with no argument and the queue holds issues 12 and 7 carrying the queue label, both unassigned, neither claimed
- **THEN** issue 7 is claimed and the `claimed` outcome carrying its brief is returned

#### Scenario: Oldest-first spans the whole queue

- **WHEN** `pickUp` is called with no argument against a queue larger than one page where an older labeled issue carries a claim marker (e.g. issue 3) and a newer unclaimed unassigned one follows past the page boundary (e.g. issue 40)
- **THEN** the oldest *eligible* issue is claimed, proving the scan reads the whole queue and skips claimed issues rather than only the first page

#### Scenario: Unassigned issues are eligible

- **WHEN** the queue holds a labeled, unclaimed issue with no assignees
- **THEN** the issue is eligible for pickup by any runner account's runs

#### Scenario: Exclusively foreign-assigned issues are invisible

- **WHEN** the queue holds labeled, unclaimed issues assigned only to other accounts
- **THEN** those issues are not eligible: the scan does not examine them for claims and posts nothing on them

#### Scenario: Among-assignees eligibility

- **WHEN** an issue carries the queue label, carries no claim marker, and is assigned to the authenticated account among several assignees
- **THEN** the issue is eligible for pickup by that account's runs

#### Scenario: No eligible issue returns a distinct outcome

- **WHEN** `pickUp` is called with no argument and every labeled issue that is not foreign-assigned is already claimed (or none carry the queue label, or every labeled issue is assigned only to other accounts)
- **THEN** the operation returns a no-eligible-issue outcome carrying the scan summary, and raises nothing

#### Scenario: Explicit number that is not eligible

- **WHEN** `pickUp` is called with the number of an issue that lacks the queue label, is assigned only to other accounts, or is already claimed
- **THEN** the operation raises an error stating which eligibility condition failed

### Requirement: Issue claim protocol

A claim SHALL be a dedicated issue comment carrying the
`<!-- ptah:issue-claim -->` marker and no protocol fields; the posting gh
account and the comment's platform timestamps carry identity and order.
The claim marker comment is the source of truth for claimedness. An
optional configured `claimedLabel` SHALL be added for human-legible queue
state only — it SHALL NOT participate in eligibility, and the queue label
SHALL NOT be removed by the playbook (it is the human's readiness
assertion).

Because multiple runners may scan one queue and GitHub offers no atomic
test-and-set, a claim SHALL be verified by reading the claims back after
posting: the winner is the earliest claim comment on the issue by the
platform's creation timestamp, with the comment's numeric
platform id as tie-break — the lowest id wins, since ids increase
monotonically with creation. Except for the claim marker itself, the
playbook SHALL write nothing to an issue before the read-back confirms
the win. The winning runner SHALL then record itself on the issue: it
adds its own account as assignee and, when configured, the
`claimedLabel` — both in that post-win slot — and SHALL NOT remove or
replace any assignee. A runner whose claim is not the earliest SHALL
back off having written nothing but its own marker — it SHALL NOT remove
its losing marker — and proceed to the next eligible issue (a scan) or
raise a lost-claim error (an explicit number). A cosmetic post-win write
that fails SHALL raise rather than proceed silently: the claim marker
remains the source of truth, and the calling script decides what a
rescan means.

There SHALL be no release protocol: a claim is audit trail, retired
naturally when the issue closes. A stale claim is cleared by a human
deleting every claim marker comment on the issue, which returns the issue
to eligibility; removing `claimedLabel` alone is cosmetic and SHALL NOT
requeue the issue. Because a losing runner leaves its losing marker in
place, a requeue means deleting all claim markers: an issue carrying only
a losing marker (its winner's marker already deleted) remains ineligible.
The assignment a winner recorded is not part of the release: a requeued
issue stays assigned to the account that claimed it, returning to that
account's queue.

#### Scenario: Earliest claim wins under contention

- **WHEN** two runners post claim comments on the same issue and both read the claims back
- **THEN** the runner whose comment is earliest by platform creation timestamp (on a tie, the lowest numeric comment id) proceeds with the brief, and the other backs off and moves on without further writes to the issue

#### Scenario: Claimed issues are not re-claimed

- **WHEN** a scan runs over a queue containing an issue that carries a claim
- **THEN** that issue is not eligible, and no second claim comment is posted on it

#### Scenario: Queue label preserved on claim

- **WHEN** a claim wins the read-back and a claimedLabel is configured
- **THEN** the claimedLabel is added after the win and the queue label remains on the issue

#### Scenario: Claimedness is the marker, not the label

- **WHEN** an issue carrying a claim marker comment has its claimedLabel removed by a human but the marker comment remains
- **THEN** the issue is still ineligible, because the label is cosmetic and the marker is the source of truth

#### Scenario: Deleting every claim marker requeues

- **WHEN** a human deletes every claim marker comment from an issue that still carries the queue label
- **THEN** the issue becomes eligible again and a later scan can claim it

#### Scenario: A losing marker alone still blocks eligibility

- **WHEN** an issue carries a claim marker posted by a losing runner (its winner's marker already deleted) and still carries the queue label
- **THEN** the issue remains ineligible until every claim marker comment is deleted

#### Scenario: The winner records itself as assignee

- **WHEN** a claim wins the read-back
- **THEN** the winning run's authenticated account is added to the issue's assignees after the read-back, and no assignee is removed or replaced

#### Scenario: A loser writes nothing but its marker

- **WHEN** a runner loses the read-back on a contended issue
- **THEN** it has written nothing to the issue except its own claim marker — no assignee change and no claimedLabel — and moves on

#### Scenario: Cosmetic write failure raises

- **WHEN** a post-win cosmetic write (self-assign or the claimedLabel) fails
- **THEN** the operation raises with the transport's error, and the claim marker remains on the issue as the source of truth

### Requirement: Pickup brief

The `claimed` outcome's `brief` SHALL carry the claimed issue's number,
url, title, body, and the claim comment's numeric platform id —
sufficient for the calling script to drive work without re-fetching the
issue. The brief SHALL carry no agent-authored content and no triage
verdict.

#### Scenario: Brief carries the work-start data

- **WHEN** a claim succeeds
- **THEN** the returned brief's `number`, `url`, `title`, `body`, and `claimCommentId` match the claimed issue and its claim comment

### Requirement: Offline test coverage

Every stdlib module and playbook entry point SHALL be exercised by an
offline test suite against the mock agent, with no network access and no
real agent. The suite is maintained in the ptah repository (this repository
ships no test suite); this requirement is the library's contract that such
coverage exists.

#### Scenario: Library regressions caught offline

- **WHEN** a library module's behavior breaks (e.g. the judge stops returning verdicts)
- **THEN** the offline suite fails without spawning any real agent
