--- Lockfile extra: pins resolved commits so compiles are reproducible.
---
--- Pure pieces (composable with laze.compile / laze.setup):
---   lock.apply(specs)      -- inject locked commits into specs (a copy)
---   lock.compile(specs)    -- apply + laze.compile
---   lock.write(compiled)   -- write lockfile from compiled pack entries
---
--- Example wiring (no setup, no commands — wire your own hooks):
---   local lock = require("laze.lock")
---   local compiled = laze.setup(lock.apply(specs))
---   -- write the lockfile after installing: lock.write(lock.compile(specs))

---@class LazeLockEntry
---@field name string
---@field src string
---@field commit string
---@field version? string

---@class LazeLock
---@field plugins LazeLockEntry[]

local laze = require("laze")
local _compile = require("laze.compile")

local M = {}

local LOCK_PATH = vim.fn.stdpath("data") .. "/laze/laze.lock"

---@return LazeLock?
local function read_lock()
	local f = io.open(LOCK_PATH, "r")
	if not f then
		return nil
	end
	local ok, data = pcall(vim.json.decode, f:read("*a"))
	f:close()
	if ok and data and data.plugins then
		return data
	end
	return nil
end

---@param lock LazeLock
local function write_lock(lock)
	vim.fn.mkdir(vim.fn.fnamemodify(LOCK_PATH, ":h"), "p")
	local f = io.open(LOCK_PATH, "w")
	if f then
		f:write(vim.json.encode(lock))
		f:close()
	end
end

---@param specs LazeSpec[]
---@return LazeSpec[]
function M.apply(specs)
	local lock = read_lock()
	if not lock then
		return specs
	end
	local by_name = {}
	for _, p in ipairs(lock.plugins) do
		by_name[p.name] = p
	end
	local out = {}
	for _, spec in ipairs(specs) do
		local name = spec.name or _compile.derive_name(spec[1] or spec.src or spec.dir or spec.url or "")
		local locked = by_name[name]
		if locked and locked.commit and not spec.commit then
			spec = vim.tbl_deep_extend("force", {}, spec, { commit = locked.commit })
		end
		table.insert(out, spec)
	end
	return out
end

---@param compiled LazeCompiled
function M.write(compiled)
	local by_src = {}
	for _, p in ipairs(compiled.pack) do
		if p.src then
			by_src[p.src] = p
		end
	end
	local plugins = {}
	for _, entry in pairs(compiled.registry) do
		local pack_entry = by_src[entry.src]
		local commit = pack_entry and (pack_entry.commit or pack_entry.version)
		if commit then
			table.insert(plugins, {
				name = entry.id,
				src = entry.src,
				commit = commit,
				version = pack_entry and pack_entry.version,
			})
		end
	end
	write_lock({ plugins = plugins })
end

---@param specs LazeSpec[]
---@param opts? { dev_root?: string }
---@return LazeCompiled
function M.compile(specs, opts)
	return laze.compile(M.apply(specs), opts)
end

return M
