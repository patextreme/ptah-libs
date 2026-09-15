## MODIFIED Requirements

### Requirement: Package consumption

The library SHALL be packaged as a pesde package (`patextreme/ptah_libs`,
`luau` target) consumable as a **git dependency pinned to a tag** of this
repository — never published to a registry — and SHALL expose exactly one
library entry whose exports are the named camelCase surface:
`std` (with `predicate`, `gh`, `daemon`, `sessionConfig`, and `escalate`),
`openspec`, `pr`, and `issue`. Top-level playbook exports are named for
the entity they manage; deep-path requires into the library tree SHALL NOT
be part of the supported consumer surface.

#### Scenario: Consumer installs as a git dependency

- **WHEN** a consumer declares a pesde git dependency on this repository at a tag revision and runs `pesde install`
- **THEN** pesde's generated `luau_packages` shim requires the package entry and re-exports its values and types, and the consumer's shim reaches the library through that generated shim

#### Scenario: Entry exports the library surface

- **WHEN** a consumer requires the generated dependency shim
- **THEN** `std.predicate`, `std.gh`, `std.daemon`, `std.sessionConfig`, `std.escalate`, `openspec`, `pr`, and `issue` are available on the returned table

#### Scenario: The renamed export replaces the former name

- **WHEN** a consumer requires the generated dependency shim
- **THEN** `prReviewLoop` is not available on the returned table (the rename is a clean break; consumers pin the prior tag to defer it)

## ADDED Requirements

### Requirement: Issue pickup playbook

The library SHALL provide an issue pickup playbook that scans a
repo-configured queue label and claims one eligible issue for the calling
script to work. The queue label SHALL be a required config value with no
default: the label vocabulary is the repository's, never the playbook's.
The playbook SHALL NOT configure agents, judges, session-config entries,
or asks — pickup is pure GitHub CLI transport (the `gh` CLI on the
agent's PATH with credentials is a declared environment requirement).

Eligibility SHALL consider only two signals: the queue label is present
and the issue carries no claim marker comment. No triage verdict or
other signal SHALL affect eligibility. The scan SHALL consider every
issue carrying the queue label, not only a fixed-size first page, and
the playbook SHALL order eligible issues oldest-first by issue number,
deterministically, regardless of queue size.

The `pickUp` operation SHALL accept either no argument (scan and claim
the oldest eligible issue) or an issue number (claim that issue only if
eligible). The operation SHALL return a typed outcome discriminated on
`status`: `claimed` carrying the pickup brief, or `no-eligible-issue`
carrying the scan summary (the count of issues scanned). A scan that
finds no eligible issue SHALL return the `no-eligible-issue` outcome
rather than raising.

When no eligible issue exists for a requested issue number, the operation
SHALL raise an error stating the reason (missing queue label or already
claimed).

#### Scenario: Consumer configures the queue label

- **WHEN** a consumer constructs the issue playbook without a queue label and runs `ptah check`
- **THEN** check reports a type or validation error naming the missing required field, and no default label is ever assumed

#### Scenario: Oldest eligible issue is picked up

- **WHEN** `pickUp` is called with no argument and the queue holds issues 12 and 7 carrying the queue label, neither claimed
- **THEN** issue 7 is claimed and the `claimed` outcome carrying its brief is returned

#### Scenario: Oldest-first spans the whole queue

- **WHEN** `pickUp` is called with no argument against a queue larger than one page where an older labeled issue carries a claim marker (e.g. issue 3 claimed) and a newer unclaimed labelled issue follows past the page boundary (e.g. issue 40)
- **THEN** the oldest *eligible* issue is claimed, proving the scan reads the whole queue and skips claimed issues rather than only the first page

#### Scenario: No eligible issue returns a distinct outcome

- **WHEN** `pickUp` is called with no argument and every queued issue is already claimed (or none carry the queue label)
- **THEN** the operation returns a no-eligible-issue outcome carrying the scan summary, and raises nothing

#### Scenario: Explicit number that is not eligible

- **WHEN** `pickUp` is called with the number of an issue that lacks the queue label or is already claimed
- **THEN** the operation raises an error stating which eligibility condition failed

### Requirement: Issue claim protocol

A claim SHALL be a dedicated issue comment carrying the
`<!-- ptah:issue-claim -->` marker and no protocol fields; the posting gh
account and the comment's platform timestamps carry identity and order.
The claim marker comment is the source of truth for claimedness. An
optional configured `claimedLabel` SHALL be added on claim for
human-legible queue state only — it SHALL NOT participate in
eligibility, and the queue label SHALL NOT be removed by the playbook
(it is the human's readiness assertion).

Because multiple runners may scan one queue and GitHub offers no atomic
test-and-set, a claim SHALL be verified by reading the claims back after
posting: the winner is the earliest claim comment on the issue by the
platform's creation timestamp, with the comment's numeric
platform id as tie-break — the lowest id wins, since ids increase
monotonically with creation. A runner
whose claim is not the earliest SHALL back off without writing anything
further to the issue — it SHALL NOT remove its own losing marker — and
proceed to the next eligible issue (a scan) or raise a lost-claim error
(an explicit number).

There SHALL be no release protocol: a claim is audit trail, retired
naturally when the issue closes. A stale claim is cleared by a human
deleting every claim marker comment on the issue, which returns the issue
to eligibility; removing `claimedLabel` alone is cosmetic and SHALL NOT
requeue the issue. Because a losing runner leaves its losing marker in
place, a requeue means deleting all claim markers: an issue carrying only
a losing marker (its winner's marker already deleted) remains ineligible.

#### Scenario: Earliest claim wins under contention

- **WHEN** two runners post claim comments on the same issue and both read the claims back
- **THEN** the runner whose comment is earliest by platform creation timestamp (on a tie, the lowest numeric comment id) proceeds with the brief, and the other backs off and moves on without further writes to the issue

#### Scenario: Claimed issues are not re-claimed

- **WHEN** a scan runs over a queue containing an issue that carries a claim
- **THEN** that issue is not eligible, and no second claim comment is posted on it

#### Scenario: Queue label preserved on claim

- **WHEN** a claim succeeds and a claimedLabel is configured
- **THEN** the claimedLabel is added and the queue label remains on the issue

#### Scenario: Claimedness is the marker, not the label

- **WHEN** an issue carrying a claim marker comment has its claimedLabel removed by a human but the marker comment remains
- **THEN** the issue is still ineligible, because the label is cosmetic and the marker is the source of truth

#### Scenario: Deleting every claim marker requeues

- **WHEN** a human deletes every claim marker comment from an issue that still carries the queue label
- **THEN** the issue becomes eligible again and a later scan can claim it

#### Scenario: A losing marker alone still blocks eligibility

- **WHEN** an issue carries a claim marker posted by a losing runner (its winner's marker already deleted) and still carries the queue label
- **THEN** the issue remains ineligible until every claim marker comment is deleted

### Requirement: Pickup brief

The `claimed` outcome's `brief` SHALL carry the claimed issue's number,
url, title, body, and the claim comment's numeric platform id —
sufficient for the calling script to drive work without re-fetching the
issue. The brief SHALL carry no agent-authored content and no triage
verdict.

#### Scenario: Brief carries the work-start data

- **WHEN** a claim succeeds
- **THEN** the returned brief's `number`, `url`, `title`, `body`, and `claimCommentId` match the claimed issue and its claim comment
