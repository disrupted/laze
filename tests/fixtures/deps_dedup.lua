return {
	specs = {
		{
			"user/parent1",
			dependencies = { "user/shared-dep", "user/only-dep1" },
			event = "VeryLazy",
		},
		{
			"user/parent2",
			dependencies = { "user/shared-dep" },
			event = "VeryLazy",
		},
		{
			"user/shared-dep",
			cmd = "SharedDepCmd",
		},
	},
}
