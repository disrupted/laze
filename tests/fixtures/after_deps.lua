return {
	specs = {
		{
			"user/plugin-a",
		},
		{
			"user/plugin-b",
			after = { "plugin-a" },
		},
		{
			"user/plugin-c",
			after = { "plugin-b", "plugin-a" },
		},
	},
}
