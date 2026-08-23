-- Fair Internal Benchmark (ms)
-- Run: nvim --cmd "set rtp+=." --headless -l tests/benchmarks/compile_compare.lua

-- Auto-detect the repo root (this script lives in tests/benchmarks/).
local script = debug.getinfo(1, "S").source:sub(2)
local LAZE_DIR = vim.env.LAZE_DIR or vim.fn.fnamemodify(script, ":h:h:h")
local LAZY_DIR = vim.env.LAZY_DIR or "/tmp/lazy.nvim"
local PLUGIN_DIR = vim.env.LAZE_PLUGINS or "/tmp/laze-plugins"

if vim.fn.isdirectory(PLUGIN_DIR) == 0 then
	error("plugin dir not found: " .. PLUGIN_DIR .. "\n  clone real plugins first: ./tests/profile/setup.sh", 0)
end
if vim.fn.isdirectory(LAZY_DIR) == 0 then
	error("lazy.nvim not found at " .. LAZY_DIR .. "\n  clone it first: git clone --depth 1 https://github.com/folke/lazy.nvim " .. LAZY_DIR, 0)
end

-- nvim -l (script mode) sets loadplugins off; lazy.nvim's setup() returns
-- early on that and leaves its Config uninitialized (crash on profile()).
-- Opt back in so the lazy.nvim side actually runs.
vim.go.loadplugins = true

vim.cmd("set rtp+=" .. LAZE_DIR)
vim.cmd("set rtp+=" .. LAZY_DIR)

local function time_it(fn)
	local start = vim.uv.hrtime()
	fn()
	return (vim.uv.hrtime() - start) / 1e6
end

local SPEC_LAZE = {
	{ dir = PLUGIN_DIR .. "/plenary.nvim" },
	{ dir = PLUGIN_DIR .. "/nui.nvim", ft = "markdown" },
	{ dir = PLUGIN_DIR .. "/which-key.nvim", event = "VeryLazy", keys = "<leader>wk" },
	{ dir = PLUGIN_DIR .. "/oil.nvim", cmd = "Oil", keys = { { lhs = "<leader>o", mode = "n" } } },
}

local SPEC_LAZY = {
	{ dir = PLUGIN_DIR .. "/plenary.nvim" },
	{ dir = PLUGIN_DIR .. "/nui.nvim", ft = "markdown" },
	{ dir = PLUGIN_DIR .. "/which-key.nvim", event = "VeryLazy", keys = "<leader>wk" },
	{ dir = PLUGIN_DIR .. "/oil.nvim", cmd = "Oil", keys = { { "<leader>o", mode = "n" } } },
}

local function run_laze_cold()
	require("laze").setup(SPEC_LAZE)
end

local function run_laze_warm()
	package.loaded["laze"] = nil
	require("laze").setup(SPEC_LAZE)
end

local function run_lazy_cold()
	require("lazy").setup(
		SPEC_LAZY,
		{ headless = { process = false, log = false, task = false, colors = false }, profile = true }
	)
	return require("lazy").profile()
end

local function median(t)
	table.sort(t)
	return t[math.ceil(#t / 2)]
end

print("=== Fair Internal Benchmark (ms) ===")
print("Spec: 4 plugins (2 eager, 2 lazy)")
print()

print("--- Cold start ---")
local laze_time = time_it(run_laze_cold)
print(string.format("laze.nvim: %.2f ms", laze_time))

local lazy_time = time_it(run_lazy_cold)
print(string.format("lazy.nvim: %.2f ms", lazy_time))

print()
print("--- Warm start (3 runs) ---")
local laze_warm = {}
for i = 1, 3 do
	table.insert(laze_warm, time_it(run_laze_warm))
end
print(string.format("laze.nvim: %.2f ms (median)", median(laze_warm)))

print()
print("--- Speedup ---")
print(string.format("Cold:  %.2fx (lazy/laze)", lazy_time / laze_time))

vim.cmd("qa!")
