## Why

The `extract-issue-worker` change added `std.agent`, `std.shell`, the
`ciGate` playbook, and the `issueWorker` meta playbook — the largest and
most behavior-dense surface in the library — with no offline coverage, and
left `README.md` claiming "at snapshot `6307bd5` ptah has no such suite
yet" even though the ptah mock-agent suite (`crates/ptah-cli/tests/ptah_libs.rs`)
now exists. The library's permanent *Offline test coverage* requirement
therefore has no backing for the new modules, and the README understates
the coverage that does exist.

## What Changes

- Add offline upstream ptah tests (mock agent, no network, no real agent)
  exercising the new library surface: `std.agent.inDirectory` force-cwd,
  `std.shell` quoting/`mustRun`/`succeeds`/`errorMessage`, the
  `std.gh`/`std.daemon` re-route through `std.shell`, `ciGate` rollup
  classification and its bounded repair loop, and `issueWorker` pickup,
  triage routes, delivery re-checks, bookkeeping, and outcome mapping.
- Correct the stale `README.md` note that the library ships no tests and
  that ptah has no suite yet; point at the real suite and state the
  coverage it provides.
- No library behavior changes and no requirement-text changes: the
  *Offline test coverage* requirement stays as written; this change makes
  it true for the new modules.

**Non-goals:** any change to the library's runtime behavior or exports;
cutting a tag (the tag is cut only after this coverage and the README
correction land).

## Capabilities

### New Capabilities

<!-- none: this change adds upstream test coverage and corrects docs; it
     changes no requirement text -->

### Modified Capabilities

<!-- none: the existing *Offline test coverage* requirement is satisfied by
     this change, not modified -->

## Impact

- `patextreme/ptah` — `crates/ptah-cli/tests/` (new offline cases for the
  new std modules and playbooks).
- `ptah-libs` `README.md` — the Versioning section's offline-coverage note.
- No library code changes; no consumer-facing export changes.
