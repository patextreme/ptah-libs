## Context

See proposal.md — Why. Today the export surface is
`{ std, openspec, prReviewLoop }` and the playbook lives at
`playbooks/pr-review-loop/`. The loop's persisted state — the ledger and
report PR comments marked `<!-- ptah:pr-review-ledger -->` /
`<!-- ptah:pr-review-report -->` — lives on GitHub, outside this
repository's control. ADR `docs/adr/0001-name-playbooks-for-entities.md`
records the entity-naming decision.

## Goals / Non-Goals

**Goals:**

- Rename the export key and the playbook directory to `pr` with zero
  behavior change in the loop itself.
- Keep every byte of persisted wire format and user-visible wording
  stable.

**Non-Goals:**

- No alias/compat export (decided against in ADR 0001).
- No new operations on the `pr` facade (the deferred scan/daemon stays
  deferred).
- No marker or prefix renames.

## Decisions

- **Rename code, freeze wire.** Directory, `lib.luau` export key, READMEs,
  and the spec's export list rename; the ledger/report marker strings,
  the `pr-review:` error and ask-identity prefixes, and session-id
  prefixes (`pr-review`, `pr-review-judge`, …) stay byte-stable. The
  markers are state on third-party infrastructure — renaming them orphans
  every in-flight ledger to a fresh discovery pass. The prefixes are
  load-bearing for humans correlating asks with sessions, and no behavior
  gain justifies churning them.
  *Alternative considered:* rename markers to `pr-ledger`/`pr-report` for
  consistency — rejected for ledger continuity; a marker migration
  (read-old-write-new) would be its own future change if ever wanted.
- **Directory rename via `git mv`** so history follows the file; the
  playbook's internal requires (`../../std/…`, `./default-instruction`,
  `./protocol`) are directory-name-independent and untouched. Only
  `lib.luau`'s require path changes.
- **Migration notes in the playbook README** as a short breaking-reshape
  section naming the one consumer edit (`prReviewLoop` → `pr` in the
  shim's require/local), matching the identus-ws-lineage precedent:
  pin the prior tag to defer.

## Risks / Trade-offs

- [A consumer upgrades unpinned and breaks on the missing `prReviewLoop`]
  → Mitigation: the pesde git dependency is tag-pinned by contract
  (Package consumption requirement); the break appears at `ptah check`
  as a nil-typed field, not at runtime.
- [A future contributor "fixes" the stale-looking `pr-review:` prefixes]
  → Mitigation: ADR 0001 records why wire and wording stay frozen; the
  playbook README's migration section restates it.

## Migration Plan

1. `git mv playbooks/pr-review-loop playbooks/pr`.
2. Update `lib.luau`: require path and export key.
3. Update `README.md` (export table, playbook index) and
   `playbooks/README.md`; add the migration-notes section to
   `playbooks/pr/README.md`.
4. Archive this change (spec delta lands in `openspec/specs/playbooks/`).
5. Tag; consumers upgrade by switching `prReviewLoop` → `pr`.

Rollback: revert the commit; the prior tag keeps serving old consumers.

## Open Questions

(none)
