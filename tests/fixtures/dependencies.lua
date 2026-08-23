return {
	specs = {
		{
			"user/plugin-main",
			dependencies = {
				"user/plugin-dep1",
				{ "user/plugin-dep2", name = "dep2-custom" },
			},
		},
	},
}
