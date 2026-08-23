return {
	specs = {
		{
			"user/plugin-build",
			build = ":TSUpdate",
			event = "VeryLazy",
		},
		{
			"user/plugin-build-fn",
			build = function()
				print("building...")
			end,
			event = "VeryLazy",
		},
		{
			"user/plugin-dev",
			dev = true,
			dev_path = "~/dev/my-plugin",
			event = "VeryLazy",
		},
	},
}
