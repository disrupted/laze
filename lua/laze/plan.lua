-- Known low-impact / accepted items live in docs/performance.md (single source).

-- Module triggers registered via package.preload across build_plan calls.
-- Module-level so a repeated build_plan (hot reload) can clear entries
-- left by its predecessor instead of accumulating stale trigger closures.
local installed_preloads = {}

---@param compiled LazeCompiled
---@param opts? { on_load?: fun(id: string, time_ms: number), on_fail?: fun(id: string, err: string) }
---@return LazePlan
local function build_plan(compiled, opts)
	opts = opts or {}
	local on_load = opts.on_load
	local on_fail = opts.on_fail
	local registry = compiled.registry
	local routes = compiled.routes
	local loaded = {}
	local startup_pending = {}
	local startup_pending_order = {}
	local startup_finalizer_installed = false
	local startup_cmd_calls = {}
	local startup_cmd_proxy_desc = "laze: defer command until VimEnter"

	-- Resolve `enabled` once at plan build time: lazy.nvim allows a function
	-- that is evaluated when the spec is processed. A function returning
	-- false means "not enabled". NOT `type(...) == "function" and f() or
	-- enabled ~= false` — that Lua gotcha turns a false-returning function
	-- into true (nil/false can't flow through and/or).
	local enabled_ok = {}
	for id, entry in pairs(registry) do
		if type(entry.enabled) == "function" then
			local ok, res = pcall(entry.enabled)
			if not ok then
				vim.notify(("laze: enabled hook failed for %s: %s"):format(id, tostring(res)), vim.log.levels.WARN)
				enabled_ok[id] = false
			else
				enabled_ok[id] = res ~= false
			end
		else
			enabled_ok[id] = entry.enabled ~= false
		end
	end

	-- Entries referenced as `after` deps are not eager (compile marks
	-- `is_dep`): eager parents pull them in at startup, lazy parents at
	-- trigger time. Mirrors lazy.nvim ("Dependencies are always lazy-loaded
	-- unless specified otherwise").

	-- Store original require before wrapping
	local original_require = require

	-- Source a plugin's own after/plugin/* scripts. :packadd sources
	-- plugin/ and ftdetect/ but NOT after/plugin (startup-only), so plugins
	-- loaded after startup need this. All files are sourced sorted; each is
	-- guarded by the plugin's own `loaded` state upstream.
	local function source_after_plugin(dir)
		local files = vim.fn.glob(dir .. "/after/plugin/**/*.{lua,vim}", false, true)
		for _, file in ipairs(files) do
			pcall(vim.cmd.source, file)
		end
	end

	-- Source glob matches under dir; each failure is contained (a broken
	-- file must not take down unrelated plugins).
	local function source_glob(dir, pattern)
		for _, file in ipairs(vim.fn.glob(dir .. pattern, false, true)) do
			pcall(vim.cmd.source, file)
		end
	end

	local function run_hooks(id, entry, start)
		if entry.init then
			local ok_init, err_init = pcall(entry.init)
			if not ok_init then
				loaded[id] = "failed"
				vim.notify("laze: init failed for " .. id .. ": " .. tostring(err_init), vim.log.levels.WARN)
				if on_fail then on_fail(id, err_init) end
				return
			end
		end
		local modules = entry.module
		if type(modules) == "string" then modules = { modules } end
		if type(modules) == "table" then
			local ok_req, err_req = pcall(function()
				for _, mod in ipairs(modules) do original_require(mod) end
			end)
			if not ok_req then
				loaded[id] = "failed"
				if not entry.silent then vim.notify("laze: failed to load " .. id .. ": " .. tostring(err_req), vim.log.levels.WARN) end
				if on_fail then on_fail(id, err_req) end
				return
			end
		end
		if entry.config then
			local ok_cfg, err_cfg = pcall(entry.config)
			if not ok_cfg then vim.notify("laze: config failed for " .. id .. ": " .. tostring(err_cfg), vim.log.levels.WARN) end
		end
		loaded[id] = true
		if on_load and start then on_load(id, (vim.uv.hrtime() - start) / 1e6) end
	end

	local function finalize_startup_pending()
		for _, id in ipairs(startup_pending_order) do
			local pending = startup_pending[id]
			if pending and loaded[id] == "pending_startup" then
				-- `:packadd!` deliberately skipped these files. Lazy opt packages
				-- can be added after Neovim's startup scan, so source them now.
				if pending.dir then
					source_glob(pending.dir, "/plugin/**/*.{lua,vim}")
					source_glob(pending.dir, "/ftdetect/*.vim")
					source_after_plugin(pending.dir)
				end
				run_hooks(id, pending.entry, pending.start)
			end
		end
	end

	local function load_plugin(id)
		if loaded[id] then
			return
		end

		local entry = registry[id]
		if not entry then
			return
		end
		if not enabled_ok[id] then
			return
		end
		-- cond may be a function (lazy.nvim) or a boolean constant. A
		-- function returning false skips the load; a throwing cond is a
		-- plan-level error: warn and skip (never throw in plan).
		local cond_ok = true
		if type(entry.cond) == "function" then
			local ok, res = pcall(entry.cond)
			if not ok then
				vim.notify(("laze: cond hook failed for %s: %s"):format(id, tostring(res)), vim.log.levels.WARN)
				cond_ok = false
			else
				cond_ok = res ~= false
			end
		else
			cond_ok = entry.cond ~= false
		end
		if not cond_ok then
			return
		end

		local start = on_load and vim.uv.hrtime() or nil
		loaded[id] = true

		-- Runtime activation: make the plugin's plugin/, ftdetect/ and
		-- after/plugin/ scripts reachable.
		--
		-- During startup (vim_did_enter == 0) the startup plugin/ and
		-- after/plugin phases source files on their own, so activation only
		-- adds the directory to the runtimepath (:packadd!) — a full
		-- :packadd would source the plugin files a second time. After
		-- startup, :packadd sources plugin/ and ftdetect/, and the missing
		-- after/plugin/ part is sourced manually (startup-only feature).
		local during_startup = vim.v.vim_did_enter == 0
		local plugin_dir
		if entry.dir then
			-- Local dir plugins are not installed by vim.pack and are added
			-- to the runtimepath by EXACT path. Never :packadd: it resolves
			-- by bare directory name across 'packpath' (`pack/*/opt/<name>`),
			-- so a stale install sharing only the basename wins and the
			-- user's dir is silently skipped (module-not-found with no hint).
			vim.opt.rtp:prepend(entry.dir)
			if not during_startup then
				-- Nothing sources these after startup (:packadd would have):
				-- do it here or commands, maps and filetype detection never
				-- exist. during_startup relies on Neovim's plugin/ phase.
				source_glob(entry.dir, "/plugin/**/*.{lua,vim}")
				source_glob(entry.dir, "/ftdetect/*.vim")
			end
			plugin_dir = entry.dir
		else
			-- Pack plugins live in pack/<pkg>/opt/<pkg>: :packadd uses the
			-- directory name (entry.pkg), which may differ from the registry
			-- id for dotted repos ("which-key" vs "which-key.nvim").
			local found = vim.fn.glob(vim.fn.stdpath("data") .. "/site/pack/*/opt/" .. entry.pkg, false, true)
			plugin_dir = found[1]
			if plugin_dir then
				local cmd = during_startup and "packadd! " or "packadd "
				pcall(vim.cmd, cmd .. vim.fn.fnameescape(entry.pkg))
			end
		end

		if during_startup and (entry.has_route or entry.is_dep) then
			loaded[id] = "pending_startup"
			startup_pending[id] = { entry = entry, dir = plugin_dir, start = start }
			table.insert(startup_pending_order, id)
			if not startup_finalizer_installed then
				startup_finalizer_installed = true
				vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = finalize_startup_pending })
			end
			return
		end

		-- after/plugin/ scripts never run on :packadd: post-startup loads
		-- source them manually, startup loads get them from the after/plugin
		-- phase (a manual source + phase would double-execute).
		if not during_startup and plugin_dir then
			source_after_plugin(plugin_dir)
		end

		run_hooks(id, entry, start)
	end

	local function load_with_deps(id)
		if loaded[id] == true or loaded[id] == "failed" or loaded[id] == "pending_startup" then
			return
		end

		-- Iterative DFS: each stack entry tracks the id and its dependency cursor.
		-- A node is popped only after load_plugin has run, so backtracking always
		-- moves to an unprocessed node. Cycle detection scans the current path.
		local stack = { id }
		local cursor = { 1 }
		local depth = 1

		while depth > 0 do
			local current = stack[depth]
			local entry = registry[current]
			local deps = entry and entry.after or {}
			local i = cursor[depth]
			if i <= #deps then
				cursor[depth] = i + 1
				local dep = deps[i]
				if loaded[dep] ~= true and loaded[dep] ~= "failed" and loaded[dep] ~= "pending_startup" then
					local has_cycle = false
					for j = 1, depth do
						if stack[j] == dep then
							vim.notify(
								("laze: cycle in after deps (%s)"):format(dep),
								vim.log.levels.WARN
							)
							has_cycle = true
							break
						end
					end
					-- Skip a cyclic dep only: the cursor was already advanced
					-- above, so the rest of the chain still loads. Aborting
					-- here would silently drop every sibling dep.
					if not has_cycle then
						depth = depth + 1
						stack[depth] = dep
						cursor[depth] = 1
					end
				end
			else
				load_plugin(current)
				depth = depth - 1
			end
		end
	end

	-- A CmdUndefined handler normally loads a plugin and lets Neovim retry the
	-- command immediately. That is sufficient after VimEnter: `:packadd`
	-- sources plugin/ synchronously, and the plugin's `:command!` definition
	-- exists before Neovim retries the original command.
	--
	-- Startup is deliberately different. load_plugin uses `:packadd!` while
	-- vim_did_enter == 0. `:packadd!` adds the plugin directory to rtp but does
	-- not source plugin/; Neovim's later startup plugin/ and after/plugin/
	-- phases do that exactly once. Using full `:packadd` here would make a
	-- command available immediately, but would also source plugin/ twice when
	-- those startup phases arrive. The activation invariant therefore wins.
	--
	-- The otherwise unavoidable gap is: CmdUndefined fires, laze activates the
	-- package with `:packadd!`, Neovim retries the command, but the plugin has
	-- not yet defined it. Install a short-lived user-command proxy before that
	-- retry. It records the fully retried invocation; VimEnter runs after the
	-- startup plugin phase, by which time a normal plugin `:command!` has
	-- replaced the proxy. We then replay the original range/bang/modifiers/
	-- arguments against the plugin command. This is only a startup bridge:
	-- post-startup command routes remain stateless CmdUndefined handlers.
	local function defer_startup_command(cmd)
		if startup_cmd_calls[cmd] then
			return
		end
		startup_cmd_calls[cmd] = {}
		vim.api.nvim_create_user_command(cmd, function(command)
			local range = ""
			if command.range == 2 then
				range = ("%d,%d"):format(command.line1, command.line2)
			elseif command.range == 1 then
				range = tostring(command.line1)
			end
			local modifiers = command.mods ~= "" and (command.mods .. " ") or ""
			local args = command.args ~= "" and (" " .. command.args) or ""
			table.insert(startup_cmd_calls[cmd], modifiers .. range .. cmd .. (command.bang and "!" or "") .. args)
		end, {
			nargs = "*",
			bang = true,
			range = true,
			bar = true,
			desc = startup_cmd_proxy_desc,
		})
		vim.api.nvim_create_autocmd("VimEnter", {
			once = true,
			callback = function()
				local calls = startup_cmd_calls[cmd]
				startup_cmd_calls[cmd] = nil
				-- A plugin's `:command!` normally replaces this proxy during the
				-- startup plugin phase. If it did not (missing package, or a
				-- plugin which does not define the advertised command), remove our
				-- proxy before replaying. Otherwise the replay would re-queue
				-- itself forever and mask the real "not an editor command" error.
				local current = vim.api.nvim_get_commands({ builtin = false })[cmd]
				if current and current.desc == startup_cmd_proxy_desc then
					pcall(vim.api.nvim_del_user_command, cmd)
				end
				for _, call in ipairs(calls or {}) do
					pcall(vim.cmd, call)
				end
			end,
		})
	end

	-- Module triggers: package.preload entries, NOT a _G.require wrapper.
	-- Zero interception of unrelated requires, zero global mutation, and
	-- each entry consumes itself on first require (single-shot, exactly
	-- like the old wrapper's table removal). The preload fn must remove
	-- its entry BEFORE load_with_deps: load_plugin requires the declared
	-- modules through original_require, which consults package.preload
	-- (the old wrapper was bypassed by original_require; preload is not).
	-- The module must exist after the load hook or require errors — same
	-- contract as the wrapper.
	-- Clear preload entries registered by a previous build_plan (hot
	-- reload): stale closures would keep firing against a dead registry.
	for name in pairs(installed_preloads) do
		package.preload[name] = nil
		installed_preloads[name] = nil
	end
	for modname, ids in pairs(routes.modules or {}) do
		installed_preloads[modname] = true
		package.preload[modname] = function()
			package.preload[modname] = nil
			installed_preloads[modname] = nil
			-- Nvim's require holds an in-flight sentinel in
			-- package.loaded while the preload fn runs; load_plugin
			-- re-requires the plugin's declared module(s), which would
			-- hit the sentinel ("loop or previous error loading
			-- module"). Clear it so the real module loads from rtp.
			package.loaded[modname] = nil
			for _, id in ipairs(ids) do
				load_with_deps(id)
			end
			return original_require(modname)
		end
	end

	return function()
		local verylazy_ids

		if next(routes.events) then
			local group = vim.api.nvim_create_augroup("laze_events", { clear = true })
			for event, ev in pairs(routes.events) do
				local ids = ev.ids
				local pattern = ev.pattern
				if event == "VeryLazy" then
					verylazy_ids = ids
					local function fire_verylazy()
						vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
					end
					vim.api.nvim_create_autocmd("UIEnter", {
						group = group,
						once = true,
						callback = fire_verylazy,
					})
					vim.api.nvim_create_autocmd("User", {
						group = group,
						pattern = "VeryLazy",
						once = true,
						callback = function()
							for _, id in ipairs(ids) do
								load_with_deps(id)
							end
						end,
					})
				else
					vim.api.nvim_create_autocmd(event, {
						group = group,
						pattern = pattern,
						once = true,
						callback = function()
							for _, id in ipairs(ids) do
								load_with_deps(id)
							end
						end,
					})
				end
			end
		end

		if next(routes.fts) then
			local group = vim.api.nvim_create_augroup("laze_fts", { clear = true })
			for ft, ids in pairs(routes.fts) do
				vim.api.nvim_create_autocmd("FileType", {
					group = group,
					pattern = ft,
					once = true,
					callback = function()
						for _, id in ipairs(ids) do
							load_with_deps(id)
						end
					end,
				})
			end

			-- A file passed on Neovim's command line can receive its FileType
			-- before init.lua reaches laze.setup(). In that case the FileType
			-- autocmd above correctly exists, but the one event it needed has
			-- already happened and the plugin would stay unloaded forever (or
			-- until another buffer with the same ft is opened). Catch up the
			-- current buffer once after registering routes. During startup this
			-- is still `:packadd!` only, so Neovim's plugin/ startup phase keeps
			-- its exactly-once sourcing responsibility; after startup it is a
			-- normal immediate ft activation.
			local function load_current_ft()
				local current_ids = routes.fts[vim.bo.filetype]
				if current_ids then
					for _, id in ipairs(current_ids) do
						load_with_deps(id)
					end
				end
			end
			load_current_ft()
			if vim.v.vim_did_enter == 0 then
				-- For command-line files the buffer can still have no filetype
				-- while init.lua runs, then receive it late in startup without a
				-- usable FileType callback. Check again once startup is complete.
				vim.api.nvim_create_autocmd("VimEnter", {
					group = group,
					once = true,
					callback = load_current_ft,
				})
			end
		end

		if next(routes.cmds) then
			local group = vim.api.nvim_create_augroup("laze_cmds", { clear = true })
			for cmd, ids in pairs(routes.cmds) do
				vim.api.nvim_create_autocmd("CmdUndefined", {
					group = group,
					pattern = cmd,
					callback = function()
						for _, id in ipairs(ids) do
							load_with_deps(id)
						end
						if vim.v.vim_did_enter == 0 then
							defer_startup_command(cmd)
						end
					end,
				})
			end
		end

		for lhs, entry in pairs(routes.keys) do
			local modes = type(entry.mode) == "table" and entry.mode or { entry.mode }
			local ids = entry.ids
			local rhs = entry.rhs
			for _, mode in ipairs(modes) do
				local keymap_opts = { desc = entry.desc or "laze: load on key" }
				if entry.silent ~= nil then
					keymap_opts.silent = entry.silent
				end
				vim.keymap.set(mode, lhs, function()
					if rhs == nil then
						-- No rhs: the plugin's own keymap takes over after load.
						-- Delete the trigger NOW — at this point it is the only
						-- map for this lhs. Deleting after loading would remove
						-- the freshly registered plugin map too (vim.keymap.del
						-- removes every map for the lhs).
						pcall(vim.keymap.del, mode, lhs)
					end
					for _, id in ipairs(ids) do
						load_with_deps(id)
					end
					if rhs == nil then
						-- Replay the key: the plugin's map (registered during
						-- load) handles it.
						vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(lhs, true, false, true), "", true)
					elseif type(rhs) == "function" then
						rhs()
					else
						vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(rhs, true, false, true), "", true)
					end
				end, keymap_opts)
			end
		end

		-- Eager plugins: load in spec order, but honor lazy.nvim `priority`
		-- (higher loads first, default 50) when explicitly set. Dependencies
		-- (`is_dep`) are excluded: they load via their parents instead.
		local eager = {}
		for _, entry in pairs(registry) do
			if enabled_ok[entry.id] and not entry.has_route and not entry.is_dep then
				table.insert(eager, entry)
			end
		end
		if #eager > 1 then
			table.sort(eager, function(a, b)
				local pa = a.priority or 50
				local pb = b.priority or 50
				if pa ~= pb then
					return pa > pb
				end
				return a.id < b.id
			end)
		end
		for _, entry in ipairs(eager) do
			load_with_deps(entry.id)
		end

		-- VeryLazy fires via a one-shot UIEnter autocmd in a normal startup
		-- (UI not yet entered). If the plan is built after startup —
		-- vim_did_enter ~= 0 — UIEnter has already fired (or, headless,
		-- will never fire) and the one-shot would be dead: fire immediately.
		if verylazy_ids and (vim.v.vim_did_enter ~= 0 or #vim.api.nvim_list_uis() == 0) then
			vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy" })
		end
	end
end

return { build_plan = build_plan }
