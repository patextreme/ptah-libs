## MODIFIED Requirements

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
present, the issue is assigned to the run's own authenticated gh account,
and the issue carries no claim marker comment. The account SHALL be the
authenticated identity itself — no config field — so the eligibility
filter and the claim share one identity. "Assigned" means the account is
among the issue's assignees, not its sole assignee: a teammate cc'd as
assignee leaves the issue eligible. No triage verdict or other signal
SHALL affect eligibility. The scan SHALL consider every labeled issue
assigned to the authenticated account, not only a fixed-size first page,
and the playbook SHALL order eligible issues oldest-first by issue
number, deterministically, regardless of queue size. The scan MAY narrow
candidates server-side by assignee; the client-side assignee check SHALL
be the authoritative eligibility signal.

The `pickUp` operation SHALL accept either no argument (scan and claim
the oldest eligible issue) or an issue number (claim that issue only if
eligible). The operation SHALL return a typed outcome discriminated on
`status`: `claimed` carrying the pickup brief, or `no-eligible-issue`
carrying the scan summary (the count of issues examined under the full
eligibility scope — labeled and assigned to the authenticated account).
A scan that finds no eligible issue SHALL return the `no-eligible-issue`
outcome rather than raising.

When no eligible issue exists for a requested issue number, the operation
SHALL raise an error stating the reason (missing queue label, not
assigned to the authenticated account, or already claimed).

#### Scenario: Consumer configures the queue label

- **WHEN** a consumer constructs the issue playbook without a queue label and runs `ptah check`
- **THEN** check reports a type or validation error naming the missing required field, and no default label is ever assumed

#### Scenario: Oldest eligible issue is picked up

- **WHEN** `pickUp` is called with no argument and the queue holds issues 12 and 7 carrying the queue label, both assigned to the authenticated account, neither claimed
- **THEN** issue 7 is claimed and the `claimed` outcome carrying its brief is returned

#### Scenario: Oldest-first spans the whole queue

- **WHEN** `pickUp` is called with no argument against a queue larger than one page where an older labeled issue assigned to the authenticated account carries a claim marker (e.g. issue 3) and a newer unclaimed one assigned to the account follows past the page boundary (e.g. issue 40)
- **THEN** the oldest *eligible* issue is claimed, proving the scan reads the whole queue and skips claimed issues rather than only the first page

#### Scenario: Unassigned or foreign-assigned issues are invisible

- **WHEN** the queue holds labeled, unclaimed issues that are assigned to no one or to another account
- **THEN** those issues are not eligible: the scan does not examine them for claims and posts nothing on them

#### Scenario: Among-assignees eligibility

- **WHEN** an issue carries the queue label, carries no claim marker, and is assigned to the authenticated account among several assignees
- **THEN** the issue is eligible for pickup by that account's runs

#### Scenario: No eligible issue returns a distinct outcome

- **WHEN** `pickUp` is called with no argument and every labeled issue assigned to the authenticated account is already claimed (or none carry the queue label, or none are assigned to the account)
- **THEN** the operation returns a no-eligible-issue outcome carrying the scan summary, and raises nothing

#### Scenario: Explicit number that is not eligible

- **WHEN** `pickUp` is called with the number of an issue that lacks the queue label, is not assigned to the authenticated account, or is already claimed
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
