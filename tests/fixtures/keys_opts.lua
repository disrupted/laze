return {
	specs = {
		{
			"user/key-plain",
			keys = { ",,x" },
		},
		{
			"user/key-desc-silent",
			keys = {
				{ ",,d", "<cmd>echo 1<CR>", desc = "my desc", silent = true },
			},
		},
	},
}
