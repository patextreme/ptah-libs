## 1. Playbook module

- [ ] 1.1 Create `playbooks/issue/playbook.luau`: `--!strict`, exported `Config` (`queueLabel` required string, `claimedLabel` optional string), `Instance` (`pickUp(self, number?) -> Outcome`), outcome types (`claimed` with brief / `no-eligible-issue`), and `M.new`; verify `ptah check` on a scratch shim reports the missing-`queueLabel` error and accepts a minimal config
- [ ] 1.2 Implement the scan through `std/gh.run` (`gh issue list` with the queue label, JSON fields number/url/title/body/labels), client-side ascending sort by number, and the eligibility filter (claimedLabel when configured); verify with a scratch run in a sandbox repo that the oldest queued, unclaimed issue is selected

## 2. Claim protocol

- [ ] 2.1 Implement the claim: per-candidate comment pre-check for the `<!-- ptah:issue-claim -->` marker, claim comment post (marker + fixed legible sentence, no data fields), optional `claimedLabel` add (queue label preserved), read-back of all claim markers, earliest-wins by `createdAt` with comment id tie-break, backoff to next candidate (scan mode) or lost-claim error (explicit mode); verify in a sandbox repo that a pre-existing claim makes the issue ineligible and that the queue label survives the claim
- [ ] 2.2 Verify contention: run two scratch `pickUp()` runs concurrently against one sandbox queue; verify exactly one winner per issue, the loser claims a different issue or returns `no-eligible-issue`, and the loser never writes a second comment to the contended issue beyond its own losing claim

## 3. Wiring and docs

- [ ] 3.1 Export `issue` from `lib.luau` (after the rename change's export table), and add index entries to `README.md` and `playbooks/README.md`; verify `grep -n "issue" README.md playbooks/README.md lib.luau` shows the three consistent mentions
- [ ] 3.2 Write `playbooks/issue/README.md` with the declared environment requirements (gh CLI on PATH with credentials; runs in the target repository; concurrent runners safe by earliest-claim; one-claim-per-issue expectation; no agent/judge/ask) and the claim protocol summary pointing at ADR 0002; verify a reader can reconstruct the whole flow from the README alone

## 4. Validation

- [ ] 4.1 Run a scratch consumer shim through `ptah check` exercising both outcome shapes (`claimed` brief fields typed, `no-eligible-issue`); run `openspec validate add-issue-playbook --strict` and verify it passes; then sync/archive per the openspec workflow
