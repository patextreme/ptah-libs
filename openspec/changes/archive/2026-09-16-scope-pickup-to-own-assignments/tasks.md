## 1. Playbook module

- [x] 1.1 Account resolution: add authenticated-login resolution to `playbooks/issue/playbook.luau` — one `gh api /user` call through `std/gh.run`, memoized on the instance so a multi-candidate scan resolves once; a failed resolution raises through the transport's outcome (its stderr in the error). Verify with a scratch run that the login matches `gh api /user --jq .login` and that a credential-less environment raises the prefixed `issue-pickup` error
- [x] 1.2 Scan narrowing: pass `assignee=<login>` to the `repos/{owner}/{repo}/issues` scan (the endpoint rejects the literal `@me` — 422 — so the resolved login is required), read each entry's `assignees` array in `mapIssue`, and add the authoritative client-side assignee check beside `hasQueueLabel` ("among the assignees", not sole); keep PR-dropping, whole-queue pagination, and the ascending-number sort. Verified in the sandbox repo `patextreme/ptah-issue-sandbox` that the oldest labeled issue **assigned to the account** wins even past a page boundary (32 assigned issues spanning 2 pages, the first 30 pre-claimed → winner on page 2), and that **unassigned** issues trigger no comments read and no writes (no marker, no label, no assignee change observed). Because the sandbox has a single assignable account, the **foreign-assigned** half was verified against the scratch `gh` transport stub in `.work/stub/` (it ignores the server-side narrowing so the authoritative client-side check is what runs): a foreign-assigned issue is excluded with no comments read and no writes
- [x] 1.3 Eligibility and errors: reorder the candidate checks to queue label → assigned-to-me → claim marker (only the marker needs a comments read); explicit `pickUp(number)` raises "not assigned to you" as its own reason beside "lacks the queue label" and "already claimed"; `scanned` counts issues examined under the full scope (labeled and assigned to the account). Verify with a scratch shim through `ptah check` that both outcome shapes still type-check and that each explicit-mode miss raises the reason matching the actual failing signal
- [x] 1.4 Winners-only writes: reorder `attempt` to pre-check → post marker → read-back → **if won** self-assign (add-assignees endpoint with the resolved login; adds, never removes) → `claimedLabel` → return brief, **if lost** return/raise having written nothing but the marker; a failing post-win cosmetic write raises with the transport's stderr and leaves the marker in place. Verified in the sandbox repo that the winner's account appears in the issue's assignees, that `claimedLabel` lands only after the win (exec order: pre-check → POST marker → read-back → self-assign → label), and that the raise path surfaces the transport error when a cosmetic write is refused (a 60-char `claimedLabel` returns 422 and the marker remains). Because the sandbox has a single assignable account, "no one removed" was verified against the scratch `gh` transport stub with a co-assignee present: the winner's add-assignees call leaves the existing foreign assignee in place

## 2. Contention and requeue verification (sandbox repo)

The sandbox repo for all sandbox verification in this change is
[`patextreme/ptah-issue-sandbox`](https://github.com/patextreme/ptah-issue-sandbox)
(private). Section 1 sandbox checks run there too; reset its issues to a
clean queue state before each scenario. The repo has a single assignable
account, so the **foreign-assigned** and **cross-account** branches cannot
be produced there; those are exercised against the scratch `gh` transport
stub in `.work/stub/` (deterministic, and the only way to reach the
authoritative client-side check, since the real `assignee=<login>`
narrowing removes foreign issues before the client check runs).

- [x] 2.1 Same-account contention: run two concurrent `pickUp()` scans against one assigned, unclaimed issue; verify exactly one winner (brief returned, assignee added), the loser writes nothing beyond its own losing marker, and deleting every marker requeues the issue — still assigned to the account, so it returns to that account's queue
- [x] 2.2 Cross-account contention ("among" semantics): with the sandbox's single assignable account (a foreign assignee cannot be created there — `GET .../assignees` returns only `patextreme` and the REST assignees endpoint drops non-assignable users), exercised against the scratch `gh` transport stub in `.work/stub/`: one labeled issue assigned to both the runner and a foreign account is eligible ("among", not sole); the earliest marker wins; the loser leaves no assignee change and no label on the issue; and an issue assigned only to the foreign account is invisible to the scan (`scanned` excludes it, with no comments read and no writes)
- [x] 2.3 Marker-as-truth regressions: confirm an issue carrying a marker stays ineligible after `claimedLabel` removal or assignee changes by humans, and that `pickUp(number)` on a labeled issue not assigned to the account raises "not assigned to you" without posting anything

## 3. Docs

- [x] 3.1 Update `playbooks/issue/README.md`: eligibility is three signals (Assignment/Eligibility terms per `CONTEXT.md`), the winners-only write sequence (nothing but the marker before the read-back; self-assign then `claimedLabel` post-win), the environment requirements gain assignee-write (triage+) and the `/user` resolution, an ops note that `scanned: 0` means nothing in the queue is assigned to the runner's account, and the **BREAKING** clean-break note (unassigned queues must pre-assign or pin the prior tag) — verify a reader can reconstruct the whole flow from the README alone
- [x] 3.2 Check `docs/adr/0002-issue-claims-earliest-marker-wins.md` still reads true next to ADR 0003 (assignees rejected as claim, adopted as scope) and cross-reference the two; verify both ADRs agree on the marker's exclusivity role

## 4. Validation

- [x] 4.1 Run a scratch consumer shim through `ptah check` exercising both outcomes and the explicit-mode errors; run `openspec validate scope-pickup-to-own-assignments --strict` and verify it passes; then sync/archive per the openspec workflow
