# The factory playbook composes its sub-playbooks internally

Three consumer repositories carried line-for-line identical ~300-line
factory shims — issue → worktree → openspec-or-direct-edit → PR →
convergent review — drifting only in Local config and repo prompt text, so
the skeleton becomes a library export, not a copyable recipe (recipes do
not converge consumers on tag bumps; shims shrink to config only when the
skeleton is a real export). The factory constructs its issue, openspec,
and pr playbook instances internally from its own data-only config;
accepting pre-built instances as config was rejected because it re-exposes
three config surfaces onto every shim and breaks "config is data" — a
playbook instance is neither data nor a ptah runtime handle. Repo
knowledge travels as free-text prompt fragments (`conventions`,
`prContract`) injected into library-owned prompt skeletons — not
structured flags, and not callbacks: a `fn(issue) -> branch` branch-naming
config was rejected on the same contract grounds, and the branch stays the
fixed `issue-<n>`.
