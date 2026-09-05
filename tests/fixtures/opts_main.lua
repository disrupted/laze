return {
	specs = {
		{
			"user/opts-plugin",
			name = "opts-plugin",
			event = "BufReadPost",
			main = "opts_plugin_mod",
			opts = { foo = 1, nested = { a = true } },
		},
		{
			"user/opts-eager",
			name = "opts-eager",
			main = "opts_eager_mod",
			opts = { bar = "x" },
		},
	},
}
