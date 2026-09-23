# The review-fix loop gates convergence on platform check state

The spec and README forbade the pr playbook from reading CI results at all
— deterministic signal ingestion and post-loop policy were the calling
script's responsibility. That boundary made the loop's "converged" claim
unfalsifiable by the one signal that means "ready" on GitHub, and a
regression introduced by the loop's own fix turn was invisible to it
forever (lace-id-portal PR #85: converged report posted while `cargo` and
`devshell` had been failing for ten minutes; green CI achieved by a fix
filed outside the loop). We reversed one half of the boundary: reading the
**platform's check state** — GitHub's own rollup verdict for a commit — is
now in scope for `reviewFixLoop` through the config-gated check gate, while
**executing repo gate commands** (running the repository's build, lint, or
test tooling) stays out forever: that is the work session's job during a
fix turn, never the playbook's. Red checks become playbook-owned ledger
findings that flow through the loop's existing fix machinery — not a
wait-for-green gate, which either hangs on a never-green lane or converges
red after a timeout, the same lie as before.

## Considered options

- **Keep CI entirely post-loop (status quo)**: rejected — the incident's
  failure mode is structural; external CI reporting to no one cannot feed
  back into a loop that has already ended.
- **A wait-for-green gate on checks**: rejected — hangs on a never-green
  lane or converges red after a timeout. Findings-not-wait routes red
  through the bounded loop (fix → re-review → cap) and keeps pending
  checks a named, non-converged outcome at budget exhaustion.
- **A separate facade verb (an `ensureCIChecksPass`-style operation)**
  composed after the review loop: rejected — sequential loops make stale
  convergence claims against each other's pushes (each push invalidates
  the other's terminal claim), violate every-push-followed-by-a-pass
  unless the second loop embeds review passes — at which point it is this
  loop duplicated on a second verb.
- **Judge-classified check findings**: rejected — the judge's prose never
  sees check state, so it can never classify or reconcile a check finding
  truthfully; ownership must be deterministic (the playbook files on red,
  closes on green, and the judge's ledger view excludes check findings).
- **Scoping check findings to loop-authored commits** (ignore failures on
  human pushes mid-run): rejected — a red check at head is a fact about
  the PR regardless of authorship, the loop's machinery is the repair
  path, and authorship tracking adds ledger state for no gating value;
  the mid-run human push is the PR-head desync case, whose recovery
  (close/reopen reattach) is documented elsewhere.

Consequences recorded in the change: the `maxIterations` default moves
8 → 10 (check-fix cycles consume units); the readiness claim (status line
and outcome) carries check state so GitHub can contradict or confirm it;
and with the gate off, behavior is unchanged.
