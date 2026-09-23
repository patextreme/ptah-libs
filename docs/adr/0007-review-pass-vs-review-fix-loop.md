# The pr facade splits the review pass from the review-fix loop

The pr playbook's single `review` operation ran the whole convergent
review→fix loop, leaving no way to review a PR without autonomous fixing.
We split the facade: `review` runs exactly one review pass — discovery or
delta, unconditionally, reporting every call — and never fixes;
`reviewFixLoop` is the prior loop behavior unchanged. The pass is the
shared atom both operations run — same ledger, judge, and reporter
machinery — and repurposing `review` is accepted under the repo's
breaking-change ritual (clean break, no alias, consumers pin the prior
tag): an old shim still runs and silently stops fixing, which is exactly
the misunderstanding this ADR exists to prevent — "making `review` fix
again" is the bug, not the repair.

## Considered options

- **Skip the pass when the ledger is already reviewed through HEAD**
  (mirroring the loop's resume fast path): rejected — an unconditional
  pass keeps the contract to one sentence; deleting the ledger is the
  documented re-review escape hatch.
- **A pass-specific outcome vocabulary** (`clean`/`findings`): rejected —
  one `Outcome` shape lets callers gate identically on either verb, and
  the report's deterministic status line is shared verbatim.
- **Retiring `review` and naming the pass `reviewPass`**: rejected — no
  silent break, but the awkward name lands on the natural verb.
- **A report comment per pass**: rejected — reports edit in place for
  both verbs; one ever-current report, with the ledger as the durable
  record of what each pass found.
