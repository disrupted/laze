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
			"user/plugin-version-false",
			version = false,
			event = "VeryLazy",
		},
		{
			"user/plugin-version-priority",
			version = "v2.0.0",
			branch = "develop",
			event = "VeryLazy",
		},
		{
			"user/plugin-commit-priority",
			branch = "main",
			tag = "v1.0.0",
			commit = "def456",
			event = "VeryLazy",
		},
	},
}
