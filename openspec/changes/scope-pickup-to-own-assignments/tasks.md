## 1. Playbook module

- [ ] 1.1 Account resolution: add authenticated-login resolution to `playbooks/issue/playbook.luau` — one `gh api /user` call through `std/gh.run`, memoized on the instance so a multi-candidate scan resolves once; a failed resolution raises through the transport's outcome (its stderr in the error). Verify with a scratch run that the login matches `gh api /user --jq .login` and that a credential-less environment raises the prefixed `issue-pickup` error
- [ ] 1.2 Scan narrowing: pass `assignee=<login>` to the `repos/{owner}/{repo}/issues` scan (the endpoint rejects the literal `@me` — 422 — so the resolved login is required), read each entry's `assignees` array in `mapIssue`, and add the authoritative client-side assignee check beside `hasQueueLabel` ("among the assignees", not sole); keep PR-dropping, whole-queue pagination, and the ascending-number sort. Verify in the sandbox repo `patextreme/ptah-issue-sandbox` that the oldest labeled issue **assigned to the account** wins even past a page boundary, and that unassigned and foreign-assigned issues trigger no comments read and no writes (observe: no marker, no label, no assignee change on them)
- [ ] 1.3 Eligibility and errors: reorder the candidate checks to queue label → assigned-to-me → claim marker (only the marker needs a comments read); explicit `pickUp(number)` raises "not assigned to you" as its own reason beside "lacks the queue label" and "already claimed"; `scanned` counts issues examined under the full scope (labeled and assigned to the account). Verify with a scratch shim through `ptah check` that both outcome shapes still type-check and that each explicit-mode miss raises the reason matching the actual failing signal
- [ ] 1.4 Winners-only writes: reorder `attempt` to pre-check → post marker → read-back → **if won** self-assign (add-assignees endpoint with the resolved login; adds, never removes) → `claimedLabel` → return brief, **if lost** return/raise having written nothing but the marker; a failing post-win cosmetic write raises with the transport's stderr and leaves the marker in place. Verify in the sandbox repo that the winner's account appears in the issue's assignees with no one removed, that `claimedLabel` lands only after the win, and that the raise path surfaces the transport error when a cosmetic write is refused

## 2. Contention and requeue verification (sandbox repo)

The sandbox repo for all sandbox verification in this change is
[`patextreme/ptah-issue-sandbox`](https://github.com/patextreme/ptah-issue-sandbox)
(private). Section 1 sandbox checks run there too; reset its issues to a
clean queue state before each scenario.

- [ ] 2.1 Same-account contention: run two concurrent `pickUp()` scans against one assigned, unclaimed issue; verify exactly one winner (brief returned, assignee added), the loser writes nothing beyond its own losing marker, and deleting every marker requeues the issue — still assigned to the account, so it returns to that account's queue
- [ ] 2.2 Cross-account contention ("among" semantics): assign one labeled issue to both sandbox accounts; verify both runners consider it eligible, the earliest marker wins, the loser leaves no assignee change and no label on the issue, and an issue assigned only to the other account is invisible to this account's scan (`scanned` excludes it)
- [ ] 2.3 Marker-as-truth regressions: confirm an issue carrying a marker stays ineligible after `claimedLabel` removal or assignee changes by humans, and that `pickUp(number)` on a labeled issue not assigned to the account raises "not assigned to you" without posting anything

## 3. Docs

- [ ] 3.1 Update `playbooks/issue/README.md`: eligibility is three signals (Assignment/Eligibility terms per `CONTEXT.md`), the winners-only write sequence (nothing but the marker before the read-back; self-assign then `claimedLabel` post-win), the environment requirements gain assignee-write (triage+) and the `/user` resolution, an ops note that `scanned: 0` means nothing in the queue is assigned to the runner's account, and the **BREAKING** clean-break note (unassigned queues must pre-assign or pin the prior tag) — verify a reader can reconstruct the whole flow from the README alone
- [ ] 3.2 Check `docs/adr/0002-issue-claims-earliest-marker-wins.md` still reads true next to ADR 0003 (assignees rejected as claim, adopted as scope) and cross-reference the two; verify both ADRs agree on the marker's exclusivity role

## 4. Validation

- [ ] 4.1 Run a scratch consumer shim through `ptah check` exercising both outcomes and the explicit-mode errors; run `openspec validate scope-pickup-to-own-assignments --strict` and verify it passes; then sync/archive per the openspec workflow
