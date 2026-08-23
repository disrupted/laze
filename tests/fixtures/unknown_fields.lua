return {
	specs = {
		{
			"user/plugin-branch",
			branch = "develop",
			event = "VeryLazy",
		},
		{
			"user/plugin-tag",
			tag = "v1.0.0",
			event = "VeryLazy",
		},
		{
			"user/plugin-commit",
			commit = "abc123",
			event = "VeryLazy",
		},
		{
			"user/plugin-pin",
			pin = true,
			event = "VeryLazy",
		},
		{
			"user/plugin-multiple",
			branch = "main",
			tag = "latest",
			commit = "def456",
			pin = false,
			event = "VeryLazy",
		},
	},
}
