# ptah-libs

The Ptah Playbooks library's home: the shared Luau workflow library for
[ptah](https://github.com/patextreme/ptah), packaged for consumption as a
pesde git dependency. This glossary covers the library's vocabulary; ptah's
own glossary covers the CLI and its workflow scripts.

## Language

**Ptah Playbooks**:
The shared workflow library maintained in this repo, consumable by any
repository. Units of it are stdlib helpers and Playbooks.
_Avoid_: Factory Components (the library's former name), shared-workflow,
bricks, lego, software factory

**stdlib**:
The repo-agnostic helper layer of Ptah Playbooks — transport, typed
judging, retry, and loop machinery. Knows nothing about any consumer repo.
_Avoid_: utils, lib, common

**Playbook**:
A reusable workflow capability that consumers compose and configure rather
than fork, named for the entity it manages — an issue, a PR, an openspec
change, or a composition of them — with its operations as that entity's
verbs.
_Avoid_: Component (the unit's former name), template, plugin, module
(module means any Luau file)

**Factory (playbook)**:
The composition playbook that drains a repository's labeled queue into
reviewed pull requests: claim an eligible issue, provision its worktree,
apply the mapped openspec change or edit directly, open the issue-linked
PR, and run the convergent PR review loop on it. Composes the issue,
openspec, and pr playbooks and constructs them internally — its Local
config is the whole composition's, data only. The name is deliberately
narrow.
_Avoid_: software factory (banned as the library's name, not this
playbook's), assembly line, pipeline

**Convergence loop**:
The core workflow pattern: prompt an agent, judge the result with a typed
predicate, and repeat with fixes until the predicate holds or the loop
escalates — a served human answer resumes the loop; an unservable or
refused escalation ends it.
_Avoid_: review loop, retry loop (those name specific uses of the pattern)

**Escalation**:
The routing decision a convergence loop makes when a judged pass hits an
operator-owned decision: an ask — pause, surface the blocker, resume
with the human's answer — when a human channel serves it; a hard fail
otherwise. A recoverable choice never escalates. The pr playbook
never escalates — the PR itself is its human checkpoint.
_Avoid_: abort (that names the human refusing an ask, not the routing),
fallback (escalation is a routing decision, not a degradation)

**Operator-owned decision**:
A decision the agent has no authority to take on the operator's behalf
— product direction, architecture, scope — and whose wrong outcome the
loop cannot reverse at bounded cost. The only justification for an ask.
_Avoid_: critical aspect (critical is a verification severity, not an
authority), human input (too broad: a confirmation is human input but
not an operator-owned decision)

**Recoverable choice**:
A decision whose wrong outcome the loop's own machinery repairs at
bounded cost — the judge rejects it, one iteration is spent. Never
justifies an ask: the agent takes it and the pass is re-judged.
_Avoid_: mechanical decision (uncheckable), confirmation (a confirmation
is a recoverable choice, not a separate category)

**Shim**:
The thin consumer-owned entry script that requires the package and hands it
Local config. The only workflow code a consumer repo owns.
_Avoid_: wrapper, bootstrap

**Local config**:
The data-only configuration table a consumer repo passes into a Playbook or
stdlib call. Functions are not configuration.
_Avoid_: settings, options file

**Prompt fragment**:
Repo-authored free text a playbook injects at a declared point of a
library-owned prompt — a repository's conventions into its direct-edit
prompt, its commit and PR contract into its delivery prompt. A fragment is
Local config: content the library places, never logic the library calls.
_Avoid_: prompt override (the prompt skeleton is never replaced), custom
prompt

**Task scope**:
The per-call description of which tasks an implement run is responsible
for. Completion — and the convergence loop's acceptance — is judged
against the scope, not against the whole change.
_Avoid_: filter (the playbook cannot see the tasks), instruction (a
scope redefines completion; an instruction does not)

**Session config**:
The ordered list of `(id, value)` entries a playbook applies to every
session it creates, via `setConfig`, in declared order — the consumer's
`setConfig` sequence as data. Order is load-bearing for agents with
dependent options.
_Avoid_: model config (model is one entry, not the concept); config
table (a table cannot carry order)

**Reviewer instruction**:
The text that tells the work agent how to review — a configured instruction
in Local config, or the playbook's built-in default. A long or repo-pinned
one points at a versioned document rather than inlining text.
_Avoid_: instruction document, review instruction, prompt

**Review pass**:
One discovery-or-delta cycle of review → typed judge → ledger write, ending
in a PR review report — the atom of PR review. A standalone review runs
exactly one pass, unconditionally, and never fixes; the review-fix loop
composes passes with fix turns under its budget.
_Avoid_: full review (discovery is full-PR, delta is not), re-review (what
deleting the ledger produces)

**Review-fix loop**:
The convergent loop over review passes and fix turns — a batched fix only
when open blocking findings remain and budget remains, every push followed
by another pass, ending converged or at the cap.
_Avoid_: review loop (the operation's former shape), fix loop (review
issues the fixes; a fix never terminates the loop)

**Ledger**:
The durable machine-readable record of a PR's review state — findings with
statuses, the discovery and last-reviewed SHAs, the PR's intention — kept
in one in-place-edited PR comment; the PR review report is its readable
view.
_Avoid_: state (too generic), findings list (the ledger carries more than
findings)

**PR review report**:
The human-facing summary of a PR review operation — one review pass or a
whole review-fix loop — posted as a marked PR comment on every terminal
outcome that returns and edited in place: one ever-current report; the
ledger carries the history. Authored by a dedicated reporter agent under a
fixed section contract, with a deterministic status line prepended by the
playbook from the ledger.
_Avoid_: verdict comment (the retired name), summary comment

**Queue label**:
The repo-configured label that places an issue into the pickup queue — a
human's assertion that the issue is ready for development. The mechanism
is the playbook's; the word is the repo's.
_Avoid_: ai-r4d (one repo's instance), intake label, ready label

**Label vocabulary**:
The declared label set a repository aligns to: name, color, and
description per label. Alignment is idempotent — create the missing,
update the drifted, never delete the unlisted. The factory playbook ships
a canonical default; a repository's own vocabulary replaces it wholesale,
never merges.
_Avoid_: label config (config is any data; the vocabulary is the label
set), label sync (sync implies two-way)

**Claim**:
An agent's posted, persistent assertion that it has taken an issue for
work. The earliest claim on an issue wins, verified by reading the claims
back.
_Avoid_: assignment (the routing signal below), lock, reservation

**Assignment**:
GitHub's assignee field as the pickup scope: an issue is eligible unless
it is foreign-assigned — it has assignees and none of them is the run's
authenticated account. An unassigned queue issue is eligible to every
runner account; a human sets assignees to steer an issue to one account
or away from others; the winning run records itself on claim, and the
playbook removes no one.
_Avoid_: claim (the marker protocol, not the routing), owner (repo owner
is a different concept)

**Eligibility**:
The three-signal gate before a claim attempt: queue label present, not
foreign-assigned (no assignees, or the authenticated account among
them), no claim marker comment. Only the marker signal needs a second
read.
_Avoid_: readiness (the queue label alone), triage (out of scope)

**Escalated**:
A triage classification meaning a human must look at the issue — persisted
on the issue for asynchronous attention, never an interactive ask.
_Avoid_: escalation (the runtime ask mechanism — a different concept),
needs-info, blocked

**Brief**:
The typed record a pickup returns — the claimed issue's identity, title,
and body plus its claim reference — from which the consumer's script
drives the work.
_Avoid_: handoff, ticket, snapshot

**ptah_libs**:
This repository as a pesde package (`patextreme/ptah_libs`, `luau`
target): one entry exposing the named camelCase exports, taken by
consumers as a git dependency pinned to a tag, never published to a
registry.
_Avoid_: ptah's factory-components tree (the frozen upstream copy this
package was moved from), the package registry (this is not published to
one)
