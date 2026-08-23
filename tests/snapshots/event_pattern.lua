local FN = require("tests.fixtures._sentinel").FN

return {
	pack = {
		{
			name = "plugin-simple",
			src = "https://github.com/user/plugin-simple",
		},
		{
			name = "plugin-pattern",
			src = "https://github.com/user/plugin-pattern",
		},
		{
			name = "plugin-array",
			src = "https://github.com/user/plugin-array",
		},
	},
	registry = {
		["plugin-array"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-array",
			is_dep = false,
			pkg = "plugin-array",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-array",
		},
		["plugin-pattern"] = {
			after = {},
			enabled = true,
			has_route = false,
			id = "plugin-pattern",
			is_dep = false,
			pkg = "plugin-pattern",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-pattern",
		},
		["plugin-simple"] = {
			after = {},
			enabled = true,
			has_route = true,
			id = "plugin-simple",
			is_dep = false,
			pkg = "plugin-simple",
			priority = 50,
			silent = false,
			src = "https://github.com/user/plugin-simple",
		},
	},
	routes = {
		cmds = {},
		events = {
			BufEnter = {
				ids = {
					"plugin-array",
				},
			},
			BufLeave = {
				ids = {
					"plugin-array",
				},
				pattern = "*.md",
			},
			BufReadPre = {
				ids = {
					"plugin-simple",
				},
			},
		},
		fts = {},
		keys = {},
		modules = {},
	},
}
