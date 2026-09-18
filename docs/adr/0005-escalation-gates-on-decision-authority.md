# Escalation gates on decision authority, not topics; the pr loop never asks

Escalation asks had a permissive bar: "cannot proceed without a human" is
satisfied by an agent that merely wants confirmation, so a cautious agent
could interrupt a human for a mechanical choice. We decided an ask is
justified only by an operator-owned decision — one the agent has no
authority to take and the loop cannot reverse at bounded cost (product
direction, architecture, and scope are examples, not the rule);
recoverable choices and confirmations never ask. The openspec playbook's
escalation probe carries that bar. The pr review loop retires its ask
entirely: `needsHuman` becomes a report-only flag for the human reviewing
the PR, which is that loop's real checkpoint.

## Considered Options

- Topic-category gate (ask only for product/architecture/design findings):
  rejected — categories misfire both ways (a naming choice is design but
  harmless to make alone; a force-push is mechanical-shaped but
  blast-radius) and the categories do not generalize across consumer repos.
- Narrowed-but-kept pr ask (mid-loop redirection for unsanctioned
  approaches): rejected — the PR is already a full human checkpoint at
  review time; the ask's remaining value, saving wasted iterations, did
  not justify keeping the trigger, adjudication session, and answer
  grammar that the 2026-09-17 change built.
- Configurable bar (`escalationAdditions` mirroring `blockingAdditions`):
  rejected — the bar is structural to the loop, like the protocol layer;
  a config field invites loosening it back toward interruption.

## Consequences

- A harder bar buys flail-to-cap failures: an agent that over-claims
  self-sufficiency burns iterations and fails loudly instead of asking.
  Accepted — the probe still catches stated inability, and cap failure
  carries the ledger and report.
- The adjudication machinery, the decisions ledger record, and the answer
  grammar in the pr playbook are deleted; reopening mid-loop human
  decisions means rebuilding them.
- Autonomy stays observable: openspec work passes note autonomous
  judgment calls in their output, and the pr report renders `needsHuman`
  flags for the reviewer.
