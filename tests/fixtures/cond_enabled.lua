return {
	specs = {
		{
			"user/plugin-cond-false",
			cond = false,
			event = "VeryLazy",
		},
		{
			"user/plugin-cond-true",
			cond = true,
			event = "VeryLazy",
		},
		{
			"user/plugin-enabled-fn",
			enabled = function()
				return false
			end,
			event = "VeryLazy",
		},
		{
			"user/plugin-module-false",
			module = false,
		},
		{
			"user/plugin-priority",
			priority = 1000,
		},
	},
}
