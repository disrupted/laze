return {
	specs = {
		{
			"folke/which-key.nvim",
			event = "VeryLazy",
			config = function()
				require("which-key").setup()
			end,
		},
		{
			"nvim-treesitter/nvim-treesitter",
			ft = { "lua", "vim" },
			config = function()
				require("nvim-treesitter.configs").setup({})
			end,
		},
		{
			"stevearc/oil.nvim",
			cmd = "Oil",
			config = function()
				require("oil").setup()
			end,
		},
	},
}
