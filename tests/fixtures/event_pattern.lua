return {
	specs = {
		{
			"user/plugin-simple",
			event = "BufReadPre",
		},
		{
			"user/plugin-pattern",
			event = { event = "BufWritePost", pattern = "*.lua" },
		},
		{
			"user/plugin-array",
			event = { "BufEnter", { event = "BufLeave", pattern = "*.md" } },
		},
	},
}
