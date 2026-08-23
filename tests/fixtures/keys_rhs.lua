return {
	specs = {
		{
			"user/keys-rhs-fn",
			keys = {
				{ ",,gb", function() end, mode = "n" },
				{ ",,o", function() end },
			},
		},
		{
			"user/keys-rhs-str",
			keys = {
				{ ",,dv", ":DiffviewOpen<CR>", mode = "n" },
			},
		},
		{
			"user/keys-mixed",
			keys = { "<leader>a", { lhs = ",,x", mode = "v" } },
		},
	},
}
