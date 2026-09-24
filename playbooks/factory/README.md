# factory playbook

The composition playbook: drain a repository's labeled issue queue into
reviewed pull requests. It composes the issue, openspec, and pr playbooks
and **constructs those instances internally** from its own data-only config
([ADR
0006](../../docs/adr/0006-factory-composition-playbook.md)) — config
accepts no playbook instances, because an instance is neither data nor a
ptah runtime handle. The stable skeleton lives here, where a tag bump
converges consumers; a consumer shim shrinks to config.

## Operations

- `factory.new(config)` — construct the factory. Raises naming the field
  when the required `queueLabel` or `base` is missing.
- `factory:issueToPR(number?)` — one issue, end to end: claim (the given
  number only if eligible — an ineligible one raises with the reason — or
  the **oldest eligible** in scan mode), relocate any live occupant of
  `issue-<n>` unless `removeOccupantWorktree` is `false` (see [The prep
  hand-off](#the-prep-hand-off)), provision its worktree on the
  fixed branch `issue-<n>` off `origin/<base>` (fetched; adopt/resume
  semantics), resolve the issue to an existing openspec change (a typed
  hand-off bounded by `resolveChangeAttempts`; an empty submitted name
  means no change applies) and drive it through groom → implement →
  verify (which syncs and archives), or implement it as a **direct edit**
  under the `conventions` fragment, then commit, push, and open the
  issue-linked pull request (the delivery prompt skeleton bounded by
  `openPullRequestAttempts`, the body carrying `Closes #<n>` so the issue
  closes on merge), and run the pr playbook's convergent review on the
  opened PR with `maxReviewIterations`. Both review end-states are the
  success path: the worktree is torn down either way.
- `factory:drain()` — loop `issueToPR()` in scan mode until the queue
  holds no eligible issue, returning the collected outcomes. The last
  element is the `no-eligible-issue` stop outcome carrying the scanned
  count. A failure of the claim phase itself (a transport error — no
  issue is involved) aborts the drain: retrying a broken scan would never
  terminate.
- `factory.initLabels(vocabulary?)` — the module-level, agent-free label
  alignment (see [Label vocabulary](#label-vocabulary) below).

## Config (data only)

Agent handles are the only non-data entries; there are no playbook
instances, no functions, no repo fields (the repository is the invocation
directory's, exactly like bare `gh`).

```lua
local factory = libs.factory.new({
	agent = ptah.agent("pi"),            -- work sessions (resolve, direct edit, delivery + the composed playbooks' work)
	judgeAgent = ptah.agent("pi"),       -- typed predicates and findings sessions
	reporterAgent = ptah.agent("pi"),    -- the PR review report's body session
	sessionConfig = { ... },             -- optional, ordered entries → every work session
	judgeSessionConfig = { ... },        -- optional, ordered entries → every judge session
	reporterSessionConfig = { ... },     -- optional, ordered entries → every reporter session
	queueLabel = "ai-r4d",               -- required, no default
	claimedLabel = "claimed",            -- optional, cosmetic queue state (issue playbook semantics)
	base = "main",                       -- required, no default
	conventions = "...",                 -- optional free-text fragment → the direct-edit prompt
	prContract = "...",                  -- optional free-text fragment → the delivery prompt
	maxReviewIterations = 10,            -- optional (default 10) → the review loop's cap
	checks = { scope = "all" },          -- optional → the review loop's check gate (pr playbook semantics); nil = gate off
	reviewInstruction = "...",           -- optional → the review persona (pr playbook persona layer); nil = built-in default
	resolveChangeAttempts = 3,           -- optional (default 3) → the resolution hand-off bound
	openPullRequestAttempts = 3,         -- optional (default 3) → the delivery hand-off bound
	removeOccupantWorktree = true,       -- optional (default true): relocate a live occupant of issue-<n> before provisioning
})
```

- **`queueLabel` and `base` have no defaults.** The queue label and the
  delivery base are the repository's, never the playbook's; `factory.new`
  raises naming the missing field.
- **One `base` field.** Each issue's worktree branches from
  `origin/<base>` and its pull request targets `base` — in every shim
  they were the same branch and never split.
- **The worktree branch is the fixed `issue-<n>`.** Three repos, zero
  variance; there is no naming callback (ADR 0006).
- **`removeOccupantWorktree` (default `true`).** Before provisioning,
  the factory relocates any live occupant of `issue-<n>` — the
  operator's prep worktree for this very issue, or a manual checkout —
  by tearing it down with default (refuse-dirty) options; the branch
  survives teardown by contract and provision re-attaches it at the
  canonical worktree. A teardown refusal fails the issue naming the
  path and the remedy. `false` skips the step: an occupied branch
  fails through provision's occupant raise, today's behavior.
- **Prompt fragments travel as data.** `conventions` rides at its
  declared injection point in the direct-edit prompt; `prContract` rides
  in the delivery prompt. The skeletons are library-owned and their
  structure is unchanged by a fragment's content — the delivery skeleton
  itself carries the mechanics every run needs (commit on the pre-created
  branch, push with `-u --force-with-lease` so a resumed run stays safe
  and the review loop's later bare `git push` lands on the PR branch,
  `Closes #<n>` in the body, `gh pr create --base <base>`, plain
  Conventional Commits). Repo law — signing, commit trailers, lint
  allowlists, CI contracts — belongs only in fragments; a fragment may
  point the agent at the repo's CI contract instead of restating it.
- **Review knobs forward verbatim.** `checks` and `reviewInstruction` are
  the pr playbook's own fields, forwarded verbatim into the internally
  constructed review loop — same names, same types, and no factory-side
  defaults, validation, or reshaping. Nil `checks` keeps the gate off (no
  check state is read — the pr playbook's opt-in semantics) and nil
  `reviewInstruction` selects the pr playbook's built-in default persona.
  The gate's semantics and budget arithmetic — scopes (`"required"` /
  `"all"`), pending-poll budget and spacing, red checks as ledger findings
  the fix turn resolves, worst-case wall clock `maxIterations ×
  pollBudgetMs` — are documented in the pr playbook, not restated here
  ([the check gate](../pr/README.md#the-check-gate-loop-only-off-by-default),
  [the instruction contract](../pr/README.md#the-instruction-contract-three-layers)).
  One consequence of the no-re-validation rule: the pr playbook is
  constructed per issue, so a malformed `checks` table fails the first
  issue with the pr playbook's `pr-review:` error — loud and immediate,
  and every subsequent issue fails identically — rather than raising at
  `factory.new`.
- **No playbook instances in config.** The factory builds its issue,
  openspec, and pr playbook instances internally — one issue instance per
  factory, one openspec/pr pair per issue worktree.

## Outcomes

Outcomes are data, discriminated on `status`:

- `pr-reviewed` — PR opened, review loop converged. Carries the issue
  `number`, `prUrl`, and the review `verdict`. With the check gate
  configured (`checks`), a converged report implies green checks at the
  reviewed head — the loop cannot end converged on red or still-pending
  in-scope checks.
- `pr-non-converged` — PR opened, review loop reached its cap with open
  blocking findings. Carries `number`, `prUrl`, `verdict`. With the gate
  configured, red checks surface as blocking check findings (same as any
  other blocking finding) and checks still pending at the poll budget's
  exhaustion end the loop non-converged. A **completed
  hand-off to the issue's human reviewer** — the worktree is torn down
  and the issue waits for its human at merge time; it is never recorded
  as a failure.
- `no-eligible-issue` — nothing left to claim; carries the scan's
  `scanned` count (issues examined under the full eligibility scope).
  The drain's stop outcome.
- `failed` — the run raised; carries the issue `number` and the error
  message.

## The laws

Policies the shims agreed on, so they are library law rather than config
and cannot drift:

- **Per-issue error boundary.** A failed issue is logged with its number
  (`factory: issue #N failed: …`) and the drain continues to the next
  eligible issue. There is no configuration surface for the boundary or
  the stop condition.
- **Teardown on the success path only.** A failed issue keeps its
  worktree in place (the audit trail; unpushed commits survive on the
  `issue-<n>` branch) and stays claimed — the claim marker is what a
  human deletes to re-queue the issue.
- **Non-converged is a hand-off, not a failure.** A capped review with
  open blocking findings is exactly what "the PR waits for its human at
  merge time" looks like; the outcome says so and the pipeline treats it
  as done.

Session ids keep the shim shapes — `factory-resolve:<n>`,
`factory-direct:<n>`, `factory-pr:<n>` — and every log line keeps the
`factory:` prefix for grep compatibility.

## The prep hand-off

Working an issue by hand before letting the factory finish it — the
contract that makes a re-queued issue just work:

1. Prepare the change in your own worktree on the issue's branch, e.g.
   `git worktree add worktrees/issue-37 origin/main -b issue-37` (any
   path works — the factory keys on the branch registration, not the
   path), and implement the change there.
2. Commit and push `issue-<n>`.
3. Re-queue the issue by deleting the claim marker (`claimedLabel`).

When the factory next claims the issue, it finds your worktree holding
`issue-<n>`, tears it down with default (refuse-dirty) options — the
relocation log names the path — and provisions its canonical worktree
on the surviving branch: your commits are preserved (provision's
fast-forward-or-fail rule keeps divergence loud), and the issue
proceeds end to end.

If your worktree is dirty (uncommitted or untracked changes), the
issue **fails** instead, naming the occupant path and the remedy —
commit, stash, or remove it by hand — with the worktree and its
contents untouched and the claim marker kept; clean it up and
re-queue. A locked worktree fails the same way (git refuses the
removal; unlocking is never the factory's act). The step relocates a
checkout; it never discards work.

Launching the factory from inside your prep worktree fails the issue
too, and leaves it untouched: the mechanism refuses to remove the
worktree the run itself is executing from — deleting it would orphan
the run's working directory and break every later git call. Launch the
factory from the shared checkout (or any directory outside the
worktree) and re-queue.

The same relocation covers a re-queued interrupted run: the earlier
run's canonical worktree is a live occupant too, so a clean one is
removed and the issue restarts fresh from `origin/<base>`, while a
dirty one fails with the remedy instead of resuming in place.

`removeOccupantWorktree = false` turns the relocation off: an occupied
branch fails through provision's occupant raise, and a branch with no
live registration provisions exactly as without the step (a stale
registration stays provision's self-heal).

## Label vocabulary

`factory.initLabels(vocabulary?)` aligns the repository's GitHub labels
to a declared vocabulary of name, color, and description — idempotent and
agent-free (pure `gh` transport, no sessions, against the invocation
directory's repository):

- create the missing labels; update drifted colors and
  declared-but-drifted descriptions; **never delete** a label outside the
  vocabulary; **no renames** (a rename would be a create plus an orphan).
- With no argument it aligns the built-in canonical default vocabulary
  (`ai-r4d` / `0e8a16` / "Ready for the automated factory queue" — the
  library home repo's values, in `default-vocabulary.luau`).
- A configured vocabulary **replaces the default wholesale, never
  merges**: exactly the configured labels are aligned and no
  default-vocabulary label is created. Unlisted labels survive untouched.
- Re-running on an aligned repository performs no writes (colors compare
  case-insensitively, `#` stripped; a vocabulary entry without a
  description leaves whatever description the label carries). Returns a
  summary: `{ created, updated, unchanged }`.

The `claimedLabel` config is not part of the vocabulary contract — it is
the issue playbook's cosmetic claimed marker, forwarded verbatim.

## Environment requirements (declared, not bundled)

- **A `pi` agent resolving in the registry** (project or user layer) for
  the work, judge, and reporter handles — the resolution, direct-edit,
  and delivery sessions run on the work handle; the openspec lifecycle
  and the review loop run through the composed playbooks.
- **`openspec` on PATH** (and the openspec skills on the work agent) for
  the groom → implement → verify path; a claimed issue whose resolution
  finds no change is the direct-edit path and needs nothing openspec.
- **`gh` authenticated** — the issue claim protocol, the delivery (`gh pr
  create`), the review loop's ledger and reports, and `initLabels` are
  all `gh` calls through `std/gh`.
- **`git` on PATH** — the worktree provision/teardown (`std/worktree`).
- **A git-ignored `.ptah/worktree/`** under the repository root — the
  worktrees' default home (see the root README's *Worktrees* section).

## Not in this playbook

- **`dryRun`** — semantically broken for the composition: the committer
  opens the PR before the review loop needs to push fixes, so a dry run
  has nothing to converge on. Explicitly out of v1.
- **`reviewPr`** — a different entity (reviewing an existing PR without
  the issue pipeline); midnight's pr-review shim stays independent.
- **Label renames and deletes** — `initLabels` never does either.
- **An openspec-less mode** — openspec is mandatory in v1; the resolve
  step already degrades to a direct edit when no change applies. Revisit
  on the first openspec-less consumer.
