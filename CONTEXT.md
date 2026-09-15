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
change — with its operations as that entity's verbs.
_Avoid_: Component (the unit's former name), template, plugin, module
(module means any Luau file)

**Convergence loop**:
The core workflow pattern: prompt an agent, judge the result with a typed
predicate, and repeat with fixes until the predicate holds or the loop
escalates — a served human answer resumes the loop; an unservable or
refused escalation ends it.
_Avoid_: review loop, retry loop (those name specific uses of the pattern)

**Escalation**:
The routing decision a convergence loop makes when a judged pass cannot
proceed without a human. Two realizations: an ask — pause, surface the
blocker, resume with the human's answer — when a human channel serves
it; a hard fail otherwise.
_Avoid_: abort (that names the human refusing an ask, not the routing),
fallback (escalation is a routing decision, not a degradation)

**Shim**:
The thin consumer-owned entry script that requires the package and hands it
Local config. The only workflow code a consumer repo owns.
_Avoid_: wrapper, bootstrap

**Local config**:
The data-only configuration table a consumer repo passes into a Playbook or
stdlib call. Functions are not configuration.
_Avoid_: settings, options file

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

**PR review report**:
The human-facing summary of a whole PR review loop, posted as a marked PR
comment (edited in place across runs) on every terminal outcome that returns.
Authored by a dedicated reporter agent under a fixed section contract, with a
deterministic status line prepended by the playbook from the ledger.
_Avoid_: verdict comment (the retired name), summary comment, review summary

**Queue label**:
The repo-configured label that places an issue into the pickup queue — a
human's assertion that the issue is ready for development. The mechanism
is the playbook's; the word is the repo's.
_Avoid_: ai-r4d (one repo's instance), intake label, ready label

**Claim**:
An agent's posted, persistent assertion that it has taken an issue for
work. The earliest claim on an issue wins, verified by reading the claims
back.
_Avoid_: assignment (GitHub's own concept), lock, reservation

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
