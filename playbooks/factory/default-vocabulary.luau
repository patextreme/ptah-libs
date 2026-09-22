--!strict
-- The built-in canonical default label vocabulary: the library home repo's
-- queue vocabulary. `initLabels()` with no argument aligns a repository to
-- exactly this. Data only — content, not logic (the
-- `pr/default-instruction.luau` pattern): a vocabulary passed to
-- `initLabels` replaces this one wholesale, never merges.

return {
	{
		name = "ai-r4d",
		color = "0e8a16",
		description = "Ready for the automated factory queue",
	},
}
