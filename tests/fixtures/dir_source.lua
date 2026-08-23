return {
	specs = {
		{
			"local-dev/my-plugin",
			dir = "/home/user/projects/my-plugin",
			keys = "<leader>p",
		},
		{
			"/tmp/other-plugin",
			cmd = "Other",
		},
		{
			"https://gitlab.com/third/plugin.nvim",
			event = "BufRead",
		},
		{
			dir = "/home/user/projects/no-name",
		},
	},
}
