## MODIFIED Requirements

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

When implement runs without a task scope, the work prompt SHALL carry a
component-owned delegation clause directing the agent to delegate
implementation by default, one subagent per **task group** — the tasks
sharing a top-level number in the tasks file (e.g. `1.1`, `1.2`, `1.3` to
one subagent; `2.1`, `2.2`, `2.3`, `2.4` to another) — passing each
subagent its group's tasks and the context it needs and having it return a
concise report carrying the tasks done, the files changed, and the
verification evidence. The agent SHALL implement directly only when
delegation would cost more than it saves. The clause SHALL NOT be
configurable away, and the orchestrating work session SHALL remain the
sole writer of the tasks file and SHALL carry each task group's outcome
into its final report, because the loop's judge judges only the
orchestrator's prose. Subagent support SHALL NOT be a hard environment
requirement: an agent unable to spawn subagents SHALL implement directly,
and delegation SHALL remain an optimization rather than an obligation.
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
- **THEN** completion is still judged against all tasks of the change, the convergence loop and escalation path are untouched, and the operation's returned text is unchanged; only the work prompt gains the delegation clause, so every other scopeless mechanic is identical to the behavior before delegation existed

#### Scenario: Scopeless implement carries the delegation clause

- **WHEN** implement runs without a task scope
- **THEN** the work prompt carries the component-owned delegation clause — directing the agent to delegate implementation by default, one subagent per task group, and to implement directly only when delegation would cost more than it saves — while the orchestrating work session remains the sole writer of the tasks file

#### Scenario: Unresolvable scope dead-ends

- **WHEN** implement runs with a task scope that matches no tasks of the change
- **THEN** the agent ends the pass stating that the scope matches no tasks without implementing a substitute subset, and the dead-end surfaces through the escalation path (an ask when a provider serves it; the operation fails otherwise)

#### Scenario: Scoped implement is unchanged by delegation

- **WHEN** implement runs with a task scope
- **THEN** the work prompt, judge acceptance, and log lines do not carry the delegation clause and are identical to the behavior before delegation existed

#### Scenario: Work sessions receive session config

- **WHEN** the playbook is configured with `sessionConfig` entries and any operation runs
- **THEN** every per-iteration work session, and verify's archive session, receives the entries in declared order before its first prompt

#### Scenario: Judge and probe sessions receive judge session config

- **WHEN** the playbook is configured with `judgeSessionConfig` entries and any operation runs
- **THEN** every judge session and every human-escalation-probe session receives the entries in declared order before its prompt

#### Scenario: Removed model field is a type error

- **WHEN** a consumer shim configures the removed `model` or `judgeModel` field and runs `ptah check`
- **THEN** check reports a type error naming the unknown field, steering the consumer to the `sessionConfig` entry form
