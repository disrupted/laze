# Opt-in extras

The core ships no commands and no runtime machinery. Everything beyond
compile → plan → setup lives as an **optional module** in `lua/laze/`
(it is never required by the core — load cost is zero unless you
`require` it). Extras are pure pieces: no `setup()`, no auto-registered
commands. You wire them explicitly into `laze.setup(specs, opts)` or
your own commands.

## `laze.lock` — lockfile

Pins resolved commits to `stdpath("data")/laze/laze.lock` and applies them on later compiles.

```lua
local laze = require("laze")
local lock = require("laze.lock")
local compiled = laze.setup(lock.apply(specs))   -- lockfile applied at compile
```

Low-level pieces: `lock.apply(specs)`, `lock.compile(specs)`, `lock.write(compiled)`.

```lua
-- sync-equivalent, as your own command (or in a one-shot call):
vim.api.nvim_create_user_command("Sync", function()
  local c = lock.compile(specs)
  vim.pack.add(c.pack)
  vim.pack.update()
  lock.write(c)
end, { desc = "Update plugins and write laze lockfile" })
```

## Manual wiring

The core exposes two small hooks on `build_plan` (`setup` passes them
through; the compiler itself stays pure):

* `on_load = fun(id, time_ms)` — called after a plugin loads successfully
* `on_fail = fun(id, err)` — called after a plugin fails to load

Use them directly — no wrapper module needed:

```lua
laze.setup(specs, {
  on_load = function(id, ms) collect(id, ms) end,
  on_fail = function(id, err) notify(id .. ": " .. err) end,
})
```