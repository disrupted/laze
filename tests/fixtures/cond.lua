return {
	specs = {
		{
			"user/plugin-always",
			cond = nil,
			event = "VeryLazy",
		},
		{
			"user/plugin-cond-false",
			cond = function()
				return false
			end,
			event = "VeryLazy",
		},
		{
			"user/plugin-cond-true",
			cond = function()
				return true
			end,
			event = "VeryLazy",
		},
	},
}
