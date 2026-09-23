# Proposal

## Why

The factory constructs the pr playbook internally, and its Local config
forwards only one review knob (`maxReviewIterations`). Two pr-playbook
options have no factory surface at all: the **check gate** (`checks`, the
#36 mechanism) and the **reviewer instruction** (`reviewInstruction`). A
factory-driven `reviewFixLoop` therefore never consults CI — no check state
is read, red checks never become ledger findings, and the loop can post
"converged" on a PR whose checks are failing or still running — and a repo
that delegates review to an external CLI loses its review persona on
migration. Observed on lace-id-portal PR #97 (run
`20260923-142333-master-pony`): the factory opened the PR at 21:28Z and the
review loop posted its converged report at 21:33Z while the `devshell`
check was `IN_PROGRESS`; the run log contains zero check-state reads.

The gap is composition debt, not a design hole: the factory landed 09-22
(#32), the gate landed on the pr playbook 09-23 (#36), and nothing re-wired
the composition afterwards. The consumer's workaround today is keeping
hand-rolled orchestration — a reimplementation of the factory's whole loop —
purely to reach config the factory doesn't expose.

## What Changes

- **Two optional fields on the factory's Local config, forwarded verbatim
  into the internal `prPlaybook.new`** (the `maxReviewIterations`
  precedent):
  - `checks: ChecksConfig?` — the check gate. Nil keeps the gate off (the
    pr playbook's existing opt-in semantics; the factory adds no default of
    its own).
  - `reviewInstruction: string?` — the review persona. Nil selects the pr
    playbook's built-in default, as today.
- **No factory-owned semantics**: same field names, same types, same nil
  behavior as the pr playbook's own config — validation stays in the pr
  playbook's constructor. Unset fields change nothing for existing
  consumers.
- **Deliberately not bundled**: whether the factory should *default* the
  gate on (e.g. `scope = "required"`, vacuously green when a repo requires
  nothing). The pr playbook deliberately made the gate opt-in — "behavior
  unchanged" when nil — and a composition-layer default would diverge from
  that philosophy. That is a separate decision; this change only asks for
  the passthrough.
- **Also out of scope**: `blockingAdditions` (the judge-facing blocking
  taxonomy) stays unexposed for now — the issue scopes the passthrough to
  the two fields above; it can ride the same pattern later on demand.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playbooks`: one requirement change. **Factory composition playbook** —
  the Local config enumeration gains the check gate (`checks`, forwarded to
  the composed review-fix loop; nil keeps the gate off) and the reviewer
  instruction (`reviewInstruction`, forwarded verbatim; nil selects the pr
  playbook's built-in default persona), with scenarios for both forwards
  and for unset-means-unchanged.

## Impact

- `playbooks/factory/playbook.luau` — two optional `Config` fields (type
  reused from the pr playbook: `prPlaybook.ChecksConfig`), two one-line
  forwards at the single internal `prPlaybook.new` site. No pr-playbook,
  stdlib, or facade changes — the pr playbook already implements and
  validates everything being forwarded.
- `playbooks/factory/README.md` — the config table gains the two entries;
  the review end-states prose names the check gate as configurable through
  the factory.
- `README.md` — the factory example config gains the two fields
  (commented).
- `openspec/specs/playbooks/spec.md` — the factory config requirement's
  field enumeration is modified (via this change's delta).
- No behavior change for any existing consumer: both fields are optional
  and default to the exact behavior shipped today.
