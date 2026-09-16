## Why

Today's shims point the playbooks at branches by mutating the shared
working tree (`git checkout` per PR/change in `pr-reviews.luau` and
`changes.luau`). That serializes work, disrupts the operator's checkout,
and blocks parallel fan-out — and the playbooks themselves are
directory-blind: every session they create runs in the invocation
directory, so a judge or reporter session that looks with its tools reads
whatever branch the shared tree happens to sit on, a silent wrong-repo
hazard. Isolated worktrees fix all three, but nothing in the library can
provision one or run inside one. The full settled design — twelve
decisions with rationale — is captured in issue #11.

## What Changes

- New stdlib module `std/worktree.luau`, exported as `std.worktree`:
  `provision` / `teardown` — the git worktree lifecycle as transport over
  ptah's exec (fetch → resolve → adopt-or-create → `worktree add`;
  remove-refuse-dirty → prune). Provision adopts an existing worktree
  as-is, fast-forwards-or-fails an existing branch against its remote
  counterpart, and never resets or renames; teardown never touches
  branches and returns its outcome as data.
- New optional config field `workingDir: string?` on the `openspec` and
  `pr` playbooks: when set, **every** session the playbook creates (work,
  judge, reporter, archive) runs in that directory; nil keeps today's
  behavior byte-for-byte. Playbooks stay git-agnostic — worktree
  lifecycle belongs to the shim.
- `std/predicate` gains an optional `cwd` option, forwarded to every
  judge attempt session, so uniform coverage reaches judge sessions.
- Documentation: root README (exports, layout, the worktree pattern) and
  both playbook READMEs (the field, the no-relative-cwd environment note).
- Dogfood retrofit (this repo's shims): `pr-reviews.luau` provisions per
  PR (head branch derived via `gh pr view --json headRefName`);
  `changes.luau` drops stacking and `landFirst` — changes go
  independent-from-main, and its resume logic collapses into
  provision's adopt / fast-forward-or-fail.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `playbooks`:
  - **Added** requirement *Worktree lifecycle* — the `std.worktree`
    provision/teardown contract (ref required, adopt-as-is,
    fast-forward-or-fail, never reset, refuse-dirty teardown, branches
    survive teardown).
  - **Added** requirement *Playbook working directory* — the
    `workingDir` config contract on the `openspec` and `pr` playbooks
    (every session, nil unchanged, documented absolute, git-agnostic).
  - **Modified** requirement *Typed judge* — options gain the optional
    `cwd` forwarded to every judge attempt session.
  - **Modified** requirement *Package consumption* — the `std` export
    enumeration gains `worktree`.

## Impact

- Code: `std/worktree.luau` (new), `std/predicate.luau`,
  `playbooks/openspec/playbook.luau`, `playbooks/pr/playbook.luau`,
  `lib.luau`.
- Docs: `README.md`, `playbooks/openspec/README.md`,
  `playbooks/pr/README.md`.
- Consumer workflows (this repo): `.ptah/workflows/adhoc/pr-reviews.luau`,
  `.ptah/workflows/adhoc/changes.luau`.
- Additive only (optional config fields, one optional option, one new
  export) — a minor bump in 0.x terms; no breaking changes.
- Environment: `provision`/`teardown` require `git` on PATH (declared,
  not bundled), like the GitHub transport requires `gh`.
