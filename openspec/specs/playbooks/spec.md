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
invocation directory), and an optional `parent` (defaulting to
`<repository root>/.ptah/worktree`, so worktrees live under the
repository's own ptah directory by default — one conventional home for
everything ptah-owned — rather than scattered as siblings of the
repository root). An explicit relative `parent` SHALL resolve against
the selected repository root, not the invocation directory. It SHALL
derive the worktree target as `<parent>/<repo-basename>-<name>`, resolve
that target to the same canonical physical absolute path Git uses for
registration, and return a record carrying that path, the branch, and
the ref. The one canonical path SHALL be used for inventory lookup,
existence checks, Git operations, diagnostics, and the returned record;
after creation, Git's registered path SHALL be authoritative. Worktree
inventory processing SHALL preserve every valid path exactly, including
paths containing spaces, non-ASCII characters, quoting characters, and
line delimiters. When the parent directory does not exist, provision
SHALL create it (including intermediate directories) before resolving
the worktree. When `fetch` is set, provision SHALL fetch the ref's
remote (a plain fetch, no refspec) before resolution.

Because the default parent sits inside the repository's checkout, a
git-ignored `<repo-root>/.ptah/worktree/` is a declared environment
requirement, like `git` on PATH: without it, every worktree is untracked
noise in `git status`. A worktree inside the checkout SHALL be treated as
an accepted, documented trade-off: `git clean -ffdx` in the shared
checkout removes nested worktree directories (a plain `git clean -fdx`
skips nested repositories; branches survive in the shared object store;
uncommitted state does not), and a consumer who cannot accept that passes
`parent` explicitly to place worktrees outside the checkout. When such a
removal (or a manual one) leaves a registration whose directory is gone —
at the target path, or at another path that holds the requested branch —
provision SHALL prune the stale registration; a stale registration at the
target path is re-created there from its surviving branch, and a stale
branch occupant falls through to target resolution. When the registration
survives the prune (a locked worktree), provision SHALL raise — unlocking
is never provision's act, and adoption never returns a path that does not
exist. Pruning is git's global `git worktree prune`, so resolving a stale
registration for the requested branch may also retire another path's stale
registration; that widening of the mechanism's one-path identity is
accepted because a stale registration is dead state no owner can use.

Provision SHALL resolve in this order, and SHALL never reset an adopted
worktree or branch — a crashed run's unpushed commits are never silently
destroyed:

- a registered worktree at the path whose directory is gone (a forced
  clean, a manual removal) is a **stale registration**: it is pruned and
  resolution falls through, re-creating the worktree at the same path
  from its surviving branch; a stale registration that survives the
  prune (a locked worktree) raises — it is never unlocked;
- a registered worktree at the path is **adopted as-is** (its branch must
  match; a mismatch, or an unregistered directory at the path, raises);
- otherwise, when the requested branch is attached to a **different**
  registered worktree (a **branch occupant**), the occupant is resolved
  before any attach: a **live** occupant raises an error naming both the
  occupant path and the target path, and the occupant is left untouched
  (provision never removes another owner's worktree); a **stale** occupant
  is pruned and resolution falls through; a stale occupant that survives
  the prune (a locked worktree) raises — it is never unlocked or removed.
  The occupant check SHALL precede the fast-forward fetch and the attach,
  because git refuses both when the branch is checked out elsewhere;
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

#### Scenario: Stale registration is pruned and the worktree re-created

- **WHEN** a worktree is registered at the derived path but its directory is gone (a `git clean -ffdx` or a manual removal)
- **THEN** provision prunes the stale registration and re-creates the worktree at the same path from the surviving branch, with the attach-as-is and fast-forward-or-fail rules applying as usual

#### Scenario: Locked stale registration raises

- **WHEN** a worktree is registered at the derived path, its directory is gone, and the registration survives the prune (a locked worktree)
- **THEN** provision raises and the locked registration is left for its owner to unlock

#### Scenario: Branch held by a live worktree raises naming both paths

- **WHEN** provision runs with a `branch` attached to a different registered worktree whose directory exists
- **THEN** provision raises an error naming both the occupant path and the target path, and the occupant worktree is left untouched — never removed, switched, or forced

#### Scenario: Branch held only by a stale registration is pruned and provisioned

- **WHEN** provision runs with a `branch` attached to a different registration whose directory is gone (a stale branch occupant)
- **THEN** provision prunes the stale registration and continues, re-creating the worktree at the target path from the surviving branch

#### Scenario: Locked stale branch occupant raises

- **WHEN** a `branch` is attached to a different registration whose directory is gone and whose registration survives the prune (a locked worktree)
- **THEN** provision raises and the locked registration is left for its owner to unlock; provision never unlocks or removes it

#### Scenario: Existing branch fast-forwards against its remote counterpart

- **WHEN** the local branch exists, `ref` is its remote-tracking counterpart, and the branch is behind the remote
- **THEN** the branch is fast-forwarded before the worktree is attached — a no-op when current, never a rebase or reset

#### Scenario: Diverged branch errors loudly

- **WHEN** the local branch has unpushed commits and its remote counterpart has moved
- **THEN** provision raises; reconciling diverged work is a human decision

#### Scenario: Resume case attaches to the surviving branch

- **WHEN** the local branch exists (a previous teardown kept it) and `ref` is that branch
- **THEN** the worktree is attached to the existing branch as-is, preserving its commits

#### Scenario: Default parent lives under the repository's ptah directory

- **WHEN** `parent` is omitted
- **THEN** the worktree path is `<repo-root>/.ptah/worktree/<repo-basename>-<name>`, canonical physical absolute, under the repository's own `.ptah` directory

#### Scenario: Path derivation stays outside the repository

- **WHEN** `parent` is passed explicitly as a directory outside any checkout
- **THEN** the worktree path is `<parent>/<repo-basename>-<name>`, canonical physical absolute, and the worktree lives outside every checkout of the repository — the opt-out for consumers who cannot accept the nested-worktree trade-off

#### Scenario: Missing parent directory is created

- **WHEN** provision runs with the derived parent directory absent (the default `.ptah/worktree` on a first run, or an explicit `parent` pointing at a fresh path)
- **THEN** the parent directory is created with its intermediate directories before the worktree is added, and provision succeeds

#### Scenario: Worktree inside the checkout requires the ignore rule

- **WHEN** a consumer relies on the default parent without git-ignoring `<repo-root>/.ptah/worktree/`
- **THEN** that is a declared environment requirement violation, like missing `git` on PATH: the mechanism proceeds, and the worktree surfaces as untracked noise in `git status` of the shared checkout

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

### Requirement: Worktree occupant introspection

The worktree mechanism SHALL export a pure introspection operation,
`liveOccupant`, that reports the path of the registered worktree
currently holding a given branch when that worktree's directory exists,
and nil when no registration holds the branch or the only registration
is stale (its directory is gone — stale state remains provision's
prune-self-heal business). The operation SHALL accept the branch
(required) and an optional repository (defaulting to the repository of
the invocation directory, like provision's `repo`). The operation SHALL
have no side effects — no prune, no creation, no removal, no fetch, no
branch inspection beyond the inventory provision already parses — and
SHALL carry no policy: it reports; it never removes. The lifecycle
requirement's occupant resolution in provision SHALL be unchanged by
this export.

#### Scenario: Live occupant is reported

- **WHEN** `liveOccupant` is called for a branch attached to a registered worktree whose directory exists
- **THEN** the operation returns that worktree's registered path and mutates nothing

#### Scenario: Stale or absent occupant is nil

- **WHEN** `liveOccupant` is called for a branch no registration holds, or whose only registration's directory is gone
- **THEN** the operation returns nil and performs no prune

#### Scenario: Optional repository defaults like provision

- **WHEN** `liveOccupant` is called without a repository from inside a repository
- **THEN** it resolves the invocation directory's repository, the same default provision applies

#### Scenario: Provision's occupant raise is unchanged

- **WHEN** provision runs for a branch attached to a live occupant
- **THEN** it raises naming both paths and leaves the occupant untouched, exactly as before the introspection export existed

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
the library's typed judge: a judge-rejected pass probes the work session,
and the probe's claim is judged by a typed predicate. An ask is justified
only by an operator-owned decision — one the agent has no authority to
take and the loop cannot reverse at bounded cost; product direction,
architecture, and scope are examples in the prompt copy, not gates. A
confirmed operator-owned decision escalates through the library's
escalation mechanism — a served ask resumes the loop with the human's
answer, and an unservable or refused ask fails the operation without
issuing a fix. A confirmation, an approval to proceed, or a recoverable
choice (a decision whose wrong outcome the judge's next rejection
repairs) never escalates: the claim fails the predicate and the loop
issues the fix prompt. Exhausting the iteration cap fails the operation
with an error reporting the cap.

Every work prompt SHALL carry a component-owned autonomy clause
instructing the agent to make judgment calls autonomously, note each in
the pass output, and never wait for confirmation; the clause SHALL NOT be
configurable away. The noted judgment calls ride the pass output, so the
operation's returned text carries every autonomous decision the agent
took.

On a confirmed operator-owned decision, the playbook SHALL ask through the
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

- **WHEN** a groom pass is judge-rejected and the escalation judge confirms the pass cannot proceed without an operator-owned decision
- **THEN** the need escalates through the library's escalation mechanism — an answered ask resumes the loop with the human's answer; an aborted or unservable ask fails the operation with an error stating human input is needed, and no fix prompt is issued

#### Scenario: Confirmation-seeking never escalates

- **WHEN** a judge-rejected pass's probe asks for confirmation, approval to proceed, or a choice among reasonable alternatives, and the escalation judge finds no operator-owned decision in the probe
- **THEN** no ask is raised; the predicate returns false, the loop issues the fix prompt, and the agent decides autonomously, noting the judgment call in its pass output

#### Scenario: Work prompts carry the autonomy clause

- **WHEN** any operation composes a work prompt
- **THEN** the component-owned autonomy clause is appended — instructing the agent to make judgment calls autonomously, note each in the pass output, and never wait for confirmation — and the noted judgment calls ride the operation's returned text

#### Scenario: Human escalation asks and resumes

- **WHEN** a groom pass is judge-rejected, the escalation judge confirms an operator-owned decision is required, an ask provider serves the request, and the human answers
- **THEN** the answer is sent verbatim as the next prompt of the still-open work session, the iteration counts against the cap, and the loop continues toward convergence

#### Scenario: Human escalation abort fails

- **WHEN** a groom pass is judge-rejected, the escalation judge confirms an operator-owned decision is required, an ask provider serves the request, and the human aborts the ask
- **THEN** the operation fails with a distinct error stating the human aborted the escalation, and no fix prompt is issued

#### Scenario: Unservable ask fails as before

- **WHEN** a groom pass is judge-rejected, the escalation judge confirms an operator-owned decision is required, and no ask provider serves the request
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

### Requirement: PR review pass

The library SHALL provide a PR review pass operation (`review`) on the pr
playbook: exactly one review pass against a pull request that never fixes.
The target repository SHALL NOT be playbook config: it arrives per call
inside the PR URL. The playbook SHALL NOT read CI results or execute
repo-specific gate commands; deterministic signal ingestion and post-review
policy are the calling script's responsibility. The playbook SHALL document
this boundary. The operation shares one `Config` with the review-fix loop
(below): `agent`, the required `judgeAgent` and `reporterAgent` handles,
`sessionConfig`, `judgeSessionConfig`, `reporterSessionConfig`,
`reviewInstruction`, `blockingAdditions`, `workingDir`, `dryRun`, and
`maxIterations`. The `model` and `judgeModel` config fields SHALL NOT
exist: a model choice is an ordinary `sessionConfig` entry.

The pass SHALL run unconditionally. With no existing ledger it runs a
discovery pass: a full-PR review whose result creates the ledger with the
discovery SHA, the `lastReviewedSha`, and the PR's intention (the PR title
and body when present; otherwise the last commit message before the first
ledger record, captured at discovery). With an existing ledger it runs a
delta review: the review prompt carries the ledger's `lastReviewedSha` and
directs the reviewer to review only the changes since that commit and to
report recurrences by ledger finding id rather than refiling them. No
ledger state SHALL gate or skip the pass — it runs even when the
`lastReviewedSha` equals the current head (deleting the ledger is the
documented re-review escape hatch).

The work session reviews freely in prose following its persona instruction
and SHALL validate blocking findings with its own in-session subagents
before finalizing its review; the directive SHALL be carried by the
component-owned protocol fragment, not the configurable persona, so a
persona replacement cannot remove it. The playbook SHALL convert the work
session's prose into structured data through a typed judge session (a
`resultSchema` result): the judge SHALL receive the review prose, the
ledger state (open and deferred findings with their ids), the PR's
intention, and the configured `blockingAdditions` text, and SHALL return
typed findings carrying per-finding severity (blocking or non-blocking), a
family name, a validation status, and the judge's `needsHuman`
determination, together with a reconciliation of the ledger's findings —
resolved (with evidence), still open, or still deferred — covering both
open and deferred entries. The judge SHALL steer findings against the PR's
intention: a finding the judge rates important but outside the PR's scope
SHALL be recorded with a deferred status in the ledger, SHALL NOT gate
convergence, and SHALL be surfaced in the PR review report's deferred
list. A recurrence of a deferred finding SHALL be reported against that
finding's id as still deferred, never refiled as a new finding. A judge
that submits no typed result SHALL be retried a bounded number of times,
and exhaustion SHALL fail the operation with a script error naming the
judge and the attempt count — never a silent outcome. The judge agent is a
required config handle: no prose-parsing fallback replaces it.

The pass SHALL apply the judge's output to the ledger exactly as the
review-fix loop does — filing open or deferred, reconciling (open → fixed
on verified-clean evidence; the judge's latest `needsHuman` determination
wins and never clears), retaining terminal `fixed` entries — and SHALL
persist the ledger in place after the pass.

The pass SHALL NOT fix, commit, or push; it SHALL NOT ask a human at any
point. `dryRun` and `maxIterations` SHALL be inert for the pass (loop-only
knobs, documented as such). After the ledger is persisted the pass SHALL
produce a PR review report per the PR review report requirement, and SHALL
return a typed outcome carrying a status (`converged` when no open
blocking findings remain after the pass, `non-converged` otherwise), the
pass's verdict prose as `verdict` (always populated — the pass always runs
one), the final ledger snapshot, and the posted report text (`report`).

#### Scenario: No ledger runs discovery

- **WHEN** `review` is called on a PR with no existing ledger
- **THEN** one full-PR review pass runs, and the result creates the ledger with the discovery SHA, the `lastReviewedSha`, and the PR's intention

#### Scenario: Existing ledger runs a delta pass

- **WHEN** `review` is called on a PR whose ledger exists
- **THEN** one delta review pass runs — the prompt carries the ledger's `lastReviewedSha` and directs the reviewer to review only the changes since that commit and to report recurrences by ledger finding id — and the ledger's `lastReviewedSha` advances to the reviewed head

#### Scenario: The pass runs even against a reviewed head

- **WHEN** `review` is called and the ledger's `lastReviewedSha` already equals the current head
- **THEN** the delta pass runs anyway (no skip fast path), the ledger persists, and a report is produced — deleting the ledger is the documented way to force a fresh discovery

#### Scenario: The pass never fixes

- **WHEN** a pass ends with open blocking findings in the ledger
- **THEN** no fix prompt is issued, nothing is committed or pushed, the outcome is `non-converged`, and the report leads with the open blocking findings

#### Scenario: Judge exhaustion fails the operation

- **WHEN** the judge session submits no typed result on every attempt up to the bound
- **THEN** the operation fails with a script error naming the judge and the attempt count, and no report is produced

#### Scenario: Deferred findings do not gate the outcome

- **WHEN** the judge defers a finding as important but outside the PR's intention
- **THEN** the finding is recorded with a deferred status, the outcome may be `converged` with it open, and the PR review report lists it under deferred findings

#### Scenario: Repository context is per-call

- **WHEN** `review` reviews a pull request
- **THEN** the repository context comes from the PR URL passed to the operation, and the playbook's config declares no repository field

#### Scenario: Loop-only knobs are inert

- **WHEN** `review` runs with `dryRun` or `maxIterations` configured
- **THEN** the pass behaves identically — it never pushes and never loops, so the knobs have no pass effect

#### Scenario: Work sessions receive session config

- **WHEN** the playbook is configured with `sessionConfig` entries and `review` runs
- **THEN** the pass's work session receives the entries in declared order before its prompt

#### Scenario: Judge sessions receive judge session config

- **WHEN** the playbook is configured with `judgeSessionConfig` entries and `review` runs
- **THEN** the pass's judge session receives the entries in declared order before its prompt

#### Scenario: Removed model field is a type error

- **WHEN** a consumer shim configures the removed `model` or `judgeModel` field and runs `ptah check`
- **THEN** check reports a type error naming the unknown field, steering the consumer to the `sessionConfig` entry form

### Requirement: PR review-fix loop

The library SHALL provide a review-fix loop operation (`reviewFixLoop`) on
the pr playbook: the convergent review→validate→fix loop composed from
review passes (per the PR review pass requirement, whose prompt, judge,
ledger, and report machinery it shares) and fix turns. The playbook SHALL
NOT read CI results or execute repo-specific gate commands; deterministic
signal ingestion and post-loop policy are the calling script's
responsibility, and the playbook SHALL document this boundary.

Convergence SHALL be computed from the judge's typed output: the loop
converges when no open blocking findings remain. The loop's budget is a
single `maxIterations` cap (default 8) over review passes. A fix turn
SHALL be issued only when open blocking findings exist and budget remains;
when the cap is reached with open findings, the loop SHALL NOT fix — it
SHALL end and report a non-converged outcome. Every pushed fix is
therefore followed by at least one review pass. A fix turn SHALL address
all open blocking findings in one turn, by root cause, and SHALL commit
and push (gated by `dryRun`). Deferred findings never gate convergence.

The work session SHALL NOT post to the pull request. For every terminal
outcome that returns (converged or non-converged), the operation SHALL
produce a PR review report per the PR review report requirement.

The loop SHALL NOT ask a human at any point: the pull request itself,
reviewed by its human at merge time, is the loop's human checkpoint. The
judge's `needsHuman` flag is report-only: the judge SHALL set it only on
an open blocking finding that rests on an operator-owned decision — one
the agent has no authority to take — that a human should examine at
review; the flag SHALL NOT be set on a deferred or non-blocking finding.
The flag persists in the ledger, renders on the finding's line in the PR
review report, and never gates, pauses, or fails the loop: an open
blocking finding carrying `needsHuman` is fixed autonomously like any
other blocking finding. A `needsHuman` determination on a non-blocking or
deferred finding, and a reconciliation record naming an id absent from the
ledger, have no loop effect: the determination persists and renders in the
report. No ask is raised, so no ask can be refused, abort, or fail for
lack of a provider: a provider-less environment behaves identically to a
served one, and the report comment is the loop's only human-facing
channel. The ledger's only writers are filing (open or deferred),
reconciliation (resolved or updated), and verification (fixed); no
mid-run path writes finding status by human decision, and no decisions
record is written (legacy decisions records are read tolerantly and
dropped on persist).

The `reviewFixLoop` operation SHALL return a typed outcome carrying a
status (`converged` / `non-converged`), the final verdict text, the final
ledger snapshot, and the posted report text (`report`).

#### Scenario: Loop composes passes and fix turns

- **WHEN** `reviewFixLoop` runs against a PR whose review leaves open blocking findings with budget remaining
- **THEN** one batched fix turn addresses all open blocking findings by root cause and commits and pushes (gated by `dryRun`), followed by another review pass, iterating until convergence or the cap

#### Scenario: First pass reviews the whole PR

- **WHEN** the loop reviews a PR with no existing ledger
- **THEN** the first review pass is a discovery pass per the PR review pass requirement

#### Scenario: Later passes review only the delta

- **WHEN** the loop runs a review pass after a fix has been pushed
- **THEN** that pass is a delta review per the PR review pass requirement

#### Scenario: Convergence is computed from typed findings

- **WHEN** the judge's typed output reports no open blocking findings
- **THEN** the loop converges and the playbook produces a PR review report whose status line reports convergence

#### Scenario: Fix never consumes the last unit

- **WHEN** the judge reports open blocking findings and the iteration cap has been reached
- **THEN** no fix turn is issued; the loop ends, the operation returns a non-converged outcome carrying the verdict text, the ledger snapshot, and the report text, and the playbook produces a non-converged PR review report

#### Scenario: Resume fast path fixes open blockers

- **WHEN** a fresh `reviewFixLoop` operation resumes a ledger holding open blocking findings — including any carrying `needsHuman` — and budget remains
- **THEN** the resume fast path issues the fix turn for them like any other open blocking finding, without an ask — the flag is the reviewer's pointer, not a gate

#### Scenario: Resume fast path converges a clean ledger at head

- **WHEN** a fresh `reviewFixLoop` operation resumes a ledger with no open blocking findings whose `lastReviewedSha` equals the current head
- **THEN** no work session runs; the report is produced from the ledger alone (no review prose) and the outcome is `converged`

#### Scenario: Resume at the cap ends without a pass

- **WHEN** a fresh `reviewFixLoop` operation resumes a ledger holding open blocking findings and the cap is already exhausted
- **THEN** no review pass and no fix turn run; the operation returns non-converged and the report renders from the ledger alone

#### Scenario: needsHuman is report-only

- **WHEN** the judge flags `needsHuman` on an open blocking finding
- **THEN** the loop issues the fix turn for it like any other blocking finding, no ask is raised, the flag persists in the ledger, and the PR review report renders it on the finding's line for the reviewing human

#### Scenario: Non-blocking needsHuman does not ask

- **WHEN** the judge flags `needsHuman` on a non-blocking or deferred finding and open blocking findings exist
- **THEN** no ask exists to raise — the loop issues the batched fix turn for the open blocking findings, and the flagged concern's `needsHuman` determination is persisted in the ledger and rendered in the PR review report

#### Scenario: Unknown reconciliation id never escalates

- **WHEN** a reconciliation record flags `needsHuman` naming an id that matches no ledger finding
- **THEN** the record has no loop effect — no ask exists to trigger — and the loop proceeds by its convergence state alone

#### Scenario: Human decision reaches the ledger only at review time

- **WHEN** a human reviews the PR after a loop run
- **THEN** human decisions land at PR review time — the merge review, guided by the report's `needsHuman` flags — never in the ledger mid-run; legacy decisions records are read tolerantly and no new ones are written

#### Scenario: The loop never asks

- **WHEN** the loop runs to a terminal outcome in any environment — with or without an ask provider
- **THEN** no ask is raised, so no ask can be refused, abort, or fail for lack of a provider; the report comment is the only human-facing channel, and it carries the ledger, the flags, and the prose

#### Scenario: Judge exhaustion fails the iteration

- **WHEN** the judge session submits no typed result on every attempt up to the bound
- **THEN** the iteration fails with a script error naming the judge and the attempt count, and no fix turn is issued

#### Scenario: Config surface

- **WHEN** a consumer constructs the playbook
- **THEN** the config is the single shared surface per the PR review pass requirement, with `maxIterations` defaulting to 8 and `dryRun` defaulting to false for the loop

#### Scenario: Operation returns a typed outcome

- **WHEN** the `reviewFixLoop` operation ends — converged, or non-converged at the cap
- **THEN** the operation returns a typed outcome carrying the status (`converged` / `non-converged`), the final verdict text, the final ledger snapshot, and the report text, rather than only a verdict string

### Requirement: PR review instruction contract

The pr playbook's documentation SHALL declare a three-layer instruction
contract, identical for both operations — every review prompt of `review`
and `reviewFixLoop` carries the same persona and protocol layers. The
**persona** layer is the reviewer instruction: a configured
`reviewInstruction` is a full replacement of the built-in default persona
(only a nil value selects the default; an empty string stays configured as
a loud misconfiguration) and carries no classification duties — the
reviewer reviews freely in prose. The **protocol** layer is a
component-owned instruction fragment appended to every review prompt at
runtime and not configurable away: the delta-review rules, the in-session
validation directive, the report-recurrences-by-ledger-id rule, and family
reuse-or-justify guidance. The **taxonomy** layer is the judge's: what
counts as blocking for the repository arrives through the
`blockingAdditions` config field (free text supplied to the judge), not
through the reviewer instruction, so the structure of either operation is
not sensitive to the quality or format of a repo-authored instruction.

The playbook's config surface (the exported `Config` type's doc comments
for `reviewInstruction` and `blockingAdditions`) SHALL state each field's
layer and role, and SHALL state which knobs are loop-only (`dryRun`,
`maxIterations`) — inert for `review`. The documentation SHALL also state
the playbook's boundary: verdicts that do not reduce to a
blocking/non-blocking classification (score gates, approve/request-changes
votes, report-only reviews) are a different playbook, not an instruction
swap, and deterministic signals (CI checks, configured gates) are outside
the playbook — they belong to the calling script.

The documentation SHALL present pointer-style instructions — reviewer
instruction text that references a repository document — as the
recommended form when the instruction is long or repo-pinned, noting that
configured text is inlined into every review prompt.

The playbook SHALL ship a built-in default persona instruction and SHALL
use it when no reviewer instruction is configured; the default carries no
classification directive (classification belongs to the judge).

#### Scenario: Instruction contract is declared

- **WHEN** a consumer consults the pr playbook's documentation before supplying a reviewer instruction
- **THEN** the three layers (persona configurable, protocol appended and not configurable away, taxonomy owned by the judge plus `blockingAdditions`) are stated, along with the boundary that verdicts not reducible to a blocking/non-blocking classification belong to a different playbook

#### Scenario: Config surface states the classification requirement

- **WHEN** a consumer reads the exported `Config` type for the pr playbook
- **THEN** `reviewInstruction`'s documentation states it is the persona (full replacement; nil selects the built-in default) with no classification duties, `blockingAdditions`' documentation states it is the judge-facing blocking taxonomy for the repository, and the loop-only knobs are marked inert for `review`

#### Scenario: Built-in default instruction used when none is configured

- **WHEN** the playbook is configured without `reviewInstruction` (the field is nil)
- **THEN** reviews run against the playbook's built-in default persona instruction, which carries no blocking/non-blocking classification directive (classification belongs to the judge)

#### Scenario: Configured instruction takes precedence

- **WHEN** `reviewInstruction` is configured with instruction text
- **THEN** the built-in default is not used — the configured text is inlined into the review prompt as the persona, the protocol fragment is still appended, and the judge still supplies the taxonomy regardless of the configured text

#### Scenario: Protocol is not configurable away

- **WHEN** any review pass runs — a lone `review` pass or a pass inside `reviewFixLoop` — with a configured persona or the built-in default
- **THEN** the review prompt carries the component-owned protocol fragment (delta rules, in-session validation directive, recurrence-by-ledger-id, family reuse guidance) in addition to the persona

#### Scenario: Pointer pattern is the documented long form

- **WHEN** a consumer consults the pr playbook's documentation with a long or repo-pinned reviewer instruction in mind
- **THEN** the documentation presents pointer-style text referencing a repository document as the recommended form

### Requirement: PR review ledger

The pr playbook SHALL persist its review state as a ledger stored in a
dedicated pull-request comment (marked
`<!-- ptah:pr-review-ledger -->` and updated in place through the library's
GitHub transport), not in playbook config or local state. The ledger SHALL
carry: the PR identity, the discovery SHA and the `lastReviewedSha`, the
PR's intention (the PR title and body when present; otherwise the last
commit message before the first ledger record, captured at discovery), the
findings with their id, family, severity, validation status, the judge's
`needsHuman` determination, status (`open` / `fixed` / `deferred` /
`accepted`), and fixing commit where applicable, and the family table. The
ledger SHALL be playbook-owned data; the documentation SHALL state that
hand-editing it is unsupported, that a deleted ledger degrades a fresh run
to a new discovery pass (today's per-run behavior), and that one
operation per PR at a time is an environment requirement (two concurrent
operations on one PR corrupt the in-place comment update). Legacy ledgers
carrying a decisions record SHALL be read tolerantly; no new decisions are
recorded.

A finding's `needsHuman` flag SHALL be recorded when the finding is filed,
SHALL be updated whenever a later reconciliation revisits the finding (the
judge's latest determination wins), and never clears — there is no mid-loop
human decision to supersede it. A ledger written before the flag existed
SHALL be read tolerantly: a finding without the field is treated as not
needing a human, and the field is written on the next persist.

Finding status SHALL be written by the judge at filing (open, or deferred
for out-of-scope concerns) and by the reconciliation path (open → fixed
when a fix is verified clean). Deferred is terminal: it has no exit
transitions, and a deferred concern that becomes in-scope again is filed
as a new open finding. `accepted` is a legacy status: read tolerantly,
terminal, and no new transition writes it (its only writer was the retired
adjudication path).

A fresh `reviewFixLoop` operation SHALL resume automatically from an
existing ledger without a resume flag: no ledger means a fresh discovery
pass; an existing ledger means the loop continues from its state (open
blocking findings — regardless of any `needsHuman` flag — drive a fix
turn; a clean ledger at the current head converges). The `review`
operation takes no resume path at all: it runs its single pass
unconditionally — discovery when no ledger exists, a delta pass otherwise
— regardless of ledger state.

Once a finding's fix has been verified clean in a later review pass, the
playbook SHALL retain it as a terminal one-line entry with status `fixed`
— its id, title, family, and fixing commit — and increment the resolved
count, rather than collapsing it to a bare count, so the PR review report
can list what was fixed. A `fixed` entry no longer participates in
reconciliation and never gates convergence. Retaining fixed entries means
the ledger grows with the PR; a ledger that outgrows the platform comment
limit fails loudly through the transport rather than truncating.

#### Scenario: Ledger created at discovery

- **WHEN** the first review pass completes on a PR with no ledger comment
- **THEN** a ledger comment is created carrying the discovery SHA, the last reviewed SHA, the PR's intention, and the typed findings with their families, validation statuses, and `needsHuman` determinations

#### Scenario: needsHuman flag persists, updates, and clears

- **WHEN** a finding is filed with `needsHuman` flagged and a later reconciliation revisits the finding
- **THEN** the ledger carries the judge's latest determination and the flag never clears — no mid-loop human decision exists to supersede it — and the PR review report renders it on the finding's line

#### Scenario: Legacy ledgers read tolerantly

- **WHEN** the playbook reads a ledger written before the `needsHuman` field existed, or one carrying a decisions record or `accepted` findings from before the ask was retired
- **THEN** findings parse without the field and are treated as not needing a human, decisions are ignored, `accepted` findings stay terminal, and the flag field is written on the next persist

#### Scenario: Decisions recorded on answered asks

- **WHEN** the playbook reads a ledger carrying a decisions record from before the ask was retired
- **THEN** no new decisions are recorded — the decisions record is never written; legacy entries are read tolerantly and dropped on the next persist

#### Scenario: Fresh run resumes from the ledger

- **WHEN** a new `reviewFixLoop` operation runs against a PR whose ledger comment exists (e.g. after a previous run ended at the cap)
- **THEN** the loop resumes from the ledger's state without a resume flag — open blocking findings (flagged or not) drive a fix turn, a clean ledger at the current head converges immediately

#### Scenario: One loop per PR is a documented requirement

- **WHEN** a consumer consults the playbook's documentation for environment requirements
- **THEN** the requirement is stated as one operation per PR at a time — a lone `review` pass corrupts in-place comment writes exactly like a loop — alongside the `gh`-based PR-host requirement, with the consequence of violating it (concurrent in-place ledger updates corrupting each other)

#### Scenario: Pass advances the ledger without a resume path

- **WHEN** a `review` operation runs against a PR whose ledger comment exists
- **THEN** the pass runs unconditionally as a delta review per the PR review pass requirement — no ledger state skips it and no fix turn precedes it

#### Scenario: Ledger updated in place after each phase

- **WHEN** a review pass or fix turn completes
- **THEN** the ledger comment is updated in place (never appended as a new comment) reflecting the new `lastReviewedSha`, finding statuses, `needsHuman` flags, and family table

#### Scenario: Intention fallback

- **WHEN** the PR has no body at discovery time
- **THEN** the ledger's intention is captured from the last commit message before the first ledger record, and later passes reuse the cached intention

#### Scenario: Resolved findings compact

- **WHEN** a finding's fix has been verified clean in a later review pass
- **THEN** the ledger retains the finding as a terminal one-line entry with status `fixed` (id, title, family, fixing commit) rather than dropping it to a bare count, increments the resolved count, and no longer treats it as open — so the PR review report can list what was fixed

### Requirement: PR review report

The pr playbook SHALL produce a **PR review report** — a human-facing
summary of a PR review operation (one review pass or a whole review-fix
loop) — as a pull-request comment marked
`<!-- ptah:pr-review-report -->` and edited in place across runs, for every
terminal outcome of a `review` or `reviewFixLoop` operation that returns
(converged and non-converged). An operation that fails — reporter
exhaustion — SHALL NOT produce a report.

The report SHALL be authored by a dedicated reporter agent: a required
`reporterAgent` config handle and an optional `reporterSessionConfig`
(applied to every reporter session in declared order). Both operations
run the reporter through the same configured handle; every call creates a
fresh reporter session. The reporter SHALL submit a typed result (a
`resultSchema` result) carrying the report body. The playbook SHALL retry
a reporter that submits no typed result a bounded number of times, and
exhaustion SHALL fail the operation with an error naming the reporter and
the attempt count — never a silent absence of the report. The converged
work session SHALL NOT author or post the report.

The playbook SHALL post and edit the report through the library's GitHub
transport, matching the ledger's marker-and-edit pattern, so a re-run —
of either operation — edits the existing report rather than appending
another: one ever-current report; the ledger carries the history. The
playbook SHALL prepend a deterministic status line derived from the ledger
— the outcome status and the count of open blocking findings — so the
report's convergence claim is never agent-authored. The reporter SHALL
author the remainder of the body under a playbook-defined section
contract.

The report body SHALL cover: the PR's intention; the resolved findings as
one-line entries; the open non-blocking findings; the deferred findings;
the accepted findings (legacy ledgers only — no new run produces them);
and a **review summary** (the operation's pass count — one for a `review`
pass, the loop's completed units for `reviewFixLoop` — plus the discovery
and last-reviewed SHAs, and the family table). For a non-converged outcome
the report SHALL lead with an open blocking findings section beneath the
status line. The resolved findings list SHALL be capped at 50 entries with
a note of how many earlier entries are omitted, so the report stays
readable while the ledger retains every entry.

The reporter session SHALL receive the full ledger, the terminal status,
and the required section contract, so the report reflects the ledger
rather than the last delta alone. It SHALL additionally receive the last
review pass's prose when a review pass ran in the current operation —
always for `review` (the pass always runs), and for `reviewFixLoop` unless
a resume converged immediately or ended at the cap without a new review
pass, in which case the prompt carries an explicit no-prose marker and the
report is rendered from the ledger alone. The ledger is the durable
whole-loop source; the prose is supplementary.

#### Scenario: Report produced on convergence

- **WHEN** a review pass converges and the operation returns
- **THEN** the playbook posts a PR review report whose status line reports convergence and whose body covers the ledger's resolved, open non-blocking, deferred, and accepted findings and the review summary

#### Scenario: Report produced on cap and leads with blockers

- **WHEN** the loop reaches the cap with open blocking findings and returns a non-converged outcome
- **THEN** the playbook posts a PR review report whose status line reports non-convergence and the open blocking count, and whose body leads with an open blocking findings section

#### Scenario: Report produced for a lone pass

- **WHEN** a `review` operation returns — converged or not
- **THEN** the playbook produces the same-shaped PR review report, with the review summary carrying a pass count of one

#### Scenario: Report is edited in place across runs

- **WHEN** a `review` or `reviewFixLoop` operation runs against a PR that already has a report comment
- **THEN** the playbook edits that comment in place rather than appending a second report

#### Scenario: Playbook owns the status line

- **WHEN** the report is produced for any outcome of either operation
- **THEN** the status line naming the outcome status and the open blocking count is composed by the playbook from the ledger, not by the reporter

#### Scenario: Reporter exhaustion fails the operation

- **WHEN** the reporter session submits no typed result on every attempt up to the bound
- **THEN** the operation fails with a script error naming the reporter and the attempt count, and no report is posted

#### Scenario: Reporter receives the full ledger and the last review prose

- **WHEN** the playbook prompts the reporter after a review pass ran in the current operation
- **THEN** the prompt carries the full ledger (including retained `fixed` entries), the terminal status, the last review pass's prose, and the section contract

#### Scenario: Reporter runs without prose on a resume

- **WHEN** a `reviewFixLoop` operation returns without running a new review pass — an immediate resume converge, or a resumed ledger already at the cap — and a report is produced
- **THEN** the reporter prompt carries the full ledger, the terminal status, and the section contract with an explicit no-prose marker instead of review prose, and the operation still returns `outcome.report`

#### Scenario: Reporter session config is applied

- **WHEN** the playbook is configured with `reporterSessionConfig` entries and a report is produced by either operation
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
`openPullRequestAttempts`), and the optional `removeOccupantWorktree`
(default `true` — whether the factory may relocate a live occupant of the
issue branch before provisioning; `false` restores provision's occupant
raise). The worktree branch for each issue SHALL be
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

#### Scenario: Occupant relocation is opt-out

- **WHEN** `factory.new` is called with `removeOccupantWorktree = false`
- **THEN** the factory performs no relocation and an occupied issue branch fails through provision's occupant raise, today's behavior

### Requirement: Factory issue-to-PR operation

The factory SHALL provide `issueToPR(number?)`: claim one issue — the
given number only if eligible, otherwise the oldest eligible — then,
when `removeOccupantWorktree` is not false, relocate any live occupant
of `issue-<n>` before provisioning: the occupant worktree is torn down
with default (refuse-dirty) options, and a teardown refusal SHALL fail
the issue naming the occupant path and the remedy (commit, stash, or
remove it by hand) with the worktree and its contents untouched. The
relocation relocates a checkout; it never discards work, and the branch
survives teardown by contract. The factory then provisions its worktree
on `issue-<n>` off `origin/<base>` — the surviving branch re-attaches
with its commits preserved under provision's fast-forward-or-fail rule —
applies the mapped openspec change or a direct edit, commits, pushes,
and opens the issue-linked pull request (its body carrying `Closes #<n>`
so the issue closes on merge), and runs the convergent PR review loop on
the opened PR. The typed hand-offs SHALL be bounded: the
change-resolution hand-off re-asks up to `resolveChangeAttempts` times
and the PR hand-off up to `openPullRequestAttempts` times, and
exhaustion SHALL fail the issue. On the success path the worktree SHALL
be torn down; a failed issue SHALL keep its worktree as the audit trail
and stay claimed.

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

#### Scenario: Prep hand-off proceeds without manual surgery

- **WHEN** the issue's branch is checked out at a prep worktree holding committed work, and the factory claims the re-queued issue
- **THEN** the prep worktree is removed, the branch re-attaches at the canonical worktree with its commits preserved, and the issue proceeds end to end

#### Scenario: Dirty occupant fails with a remedy

- **WHEN** the live occupant of the issue branch contains uncommitted or untracked changes
- **THEN** the issue fails naming the occupant path and the commit/stash/remove remedy; the worktree and its contents are untouched, and the claim marker stays

#### Scenario: Unoccupied branch behaves as before

- **WHEN** no live registration holds the issue branch (none at all, or only a stale registration whose directory is gone)
- **THEN** provisioning behaves exactly as without the relocation step, stale state still provision's self-heal

#### Scenario: Re-queued interrupted run restarts fresh or fails loudly

- **WHEN** an earlier run of the same issue left its canonical worktree in place and the issue is re-queued
- **THEN** the relocation applies identically: a clean worktree is removed and the issue restarts fresh from `origin/<base>`, while a dirty worktree fails the issue with the remedy instead of resuming in place

### Requirement: Factory drain loop

The factory SHALL provide `drain()`: repeat the issue-to-PR operation in
scan mode until the queue holds no eligible issue, returning the
collected per-issue outcomes with the terminal no-eligible-issue outcome
as the last element. Each issue SHALL run behind a per-issue error
boundary — a failed issue is logged with its failure message and the loop
continues to the next eligible issue — and the stop condition SHALL be
the issue pickup's no-eligible-issue outcome, reported with the scan's
count of eligible issues examined. A failure of the claim phase itself
(a transport error, no issue involved) SHALL abort the drain instead of
re-entering a broken scan.

#### Scenario: Drains until the queue is empty

- **WHEN** `drain()` runs against a queue holding three eligible issues and no more arrive
- **THEN** three end-to-end runs happen and the returned outcome list carries the three issue outcomes followed by the terminal no-eligible-issue outcome

#### Scenario: One failure does not stop the drain

- **WHEN** the second of four eligible issues fails mid-run
- **THEN** the failure is logged with the issue number, the remaining two issues are still worked, and all four issue outcomes appear in the returned list followed by the terminal no-eligible-issue outcome

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

### Requirement: Offline test coverage

Every stdlib module and playbook entry point SHALL be exercised by an
offline test suite against the mock agent, with no network access and no
real agent. The suite is maintained in the ptah repository (this repository
ships no test suite); this requirement is the library's contract that such
coverage exists.

#### Scenario: Library regressions caught offline

- **WHEN** a library module's behavior breaks (e.g. the judge stops returning verdicts)
- **THEN** the offline suite fails without spawning any real agent
