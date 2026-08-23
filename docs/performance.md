# Performance

Status: 2026-08, Neovim 0.12.4. Measured by `tests/run.lua perf`:

```
compile 50 plugins:        ~3.7 ms  (threshold 20ms)
build_plan 50 plugins:     ~0.06 ms (threshold 50ms)
plan execution (30 eager): ~2.5 ms  (threshold 30ms)
```

All critical paths are one-shot (compile/setup) or deferred (load time).
Nothing in the startup path scales with plugin count beyond O(N) table
walks. Items below are grouped by status.

## Resolved

### plan.lua: per-plugin runtimepath rescan on the startup fast path — resolved (2026-08)

The startup fast path called `nvim_list_runtime_paths()` and rescanned every
entry for each plugin hitting it (`O(E × R)`). One pass now builds a
closure-local `{ pkg → dir }` index on first use; plan-owned runtimepath
mutations invalidate it, and misses keep the glob + `:packadd` fallback.
Headless micro-bench (33 rtp entries, 15 fast-path lookups): 110.6 → 9.7 µs
per startup. Staleness analysis, invalidation rules, and rejected
alternatives: [rtp-index.md](rtp-index.md).

### plan.lua: redundant glob + `:packadd!` for already-active plugins — resolved (2026-08)

`vim.pack.add(..., { load = false })` already runs `:packadd!` per eager
plugin before the plan executes; the plan's own activation then repeated
a directory glob plus another `:packadd!` (an rtp-deduped no-op that
still costs an API roundtrip). During startup the plan now checks the
runtimepath first (`active_pack_dir`, mirroring the glob's
`pack/*/opt/<pkg>` shape and first-match rule) and skips both when the
directory is present; post-startup loads keep the full path (`:packadd`
without bang is what sources `plugin/`). Also hoisted
`stdpath("data")` to plan scope and added a no-deps fast path to
`load_with_deps`. Spawned-session A/B (40 specs, 20 eager): setup median
~51 ms vs ~61 ms baseline; semantics identical (eager sourced once,
rtp state equal). compile-side: removed the dead `repo_name`
computation (one unused `derive_name` chain per spec): 0.37 → 0.28 ms
per 50-spec compile (best-of-30).

### compile.lua: per-spec table literals — resolved (2026-08, c8ac8e5)

`validate_triggers`/`validate_spec` built `{ "event", "ft", "cmd", "keys" }`
etc. per spec — LuaJIT does not fold constant table constructors in
loops, so most of the compile time went to throwaway allocs and GC.
Hoisted to module constants: 1000-spec compile 27.1ms → 11.5ms (2.3x),
real-plugin cold start 9.58ms → 7.19ms.

### plan.lua: O(N×M) route scan on every startup — resolved

Formerly `plugin_has_routes()` walked all routes × entries × IDs per
plugin (O(N×M)). Now `has_route` is computed **at compile time** per
registry entry (compile.lua: `#norm.event > 0 or #norm.ft > 0 or
#norm.cmd > 0 or #norm.keys > 0 or module trigger`) and the plan's
eager loop is O(N) with O(1) per entry (`entry.has_route`, plan.lua).

### plan.lua: `_G.require` wrapper — resolved (replaced by `package.preload`)

Module triggers were implemented by replacing `_G.require` at plan build
time — a per-require call overhead on **every require in the session**,
even without `module` fields. Now each trigger is a `package.preload`
entry (plan.lua): zero interception of unrelated requires, no global
mutation, and each entry consumes itself on first require (single-shot).
`installed_preloads` tracks entries across `build_plan` calls so hot
reloads clear stale closures. Regression-tested in `tests/run.lua`
(unrelated requires untouched, entry consumed, stale entries cleared).

### plan.lua: `vim.keymap.del` + `nvim_feedkeys` — resolved (design pinned)

Takeover keys (no `rhs`): delete the trigger mapping **before** loading
(`vim.keymap.del` removes *every* map for the lhs — deleting after load
would kill the plugin's own fresh map), then replay with
`nvim_feedkeys(_, "", true)` (default flags; no `"n"` no-remap — the
plugin's own map must receive the key). `<leader>` expands against the
current `g:mapleader` at replay time. See plan.lua.

## Accepted by design (no action)

### compile.lua: `vim.fn.expand` per dev spec

One `expand()` API call per dev spec, compile is one-shot. Reads
`$HOME`. Acceptable.

### plan.lua: `vim.keymap.set` with function callback

Registering a Lua callback is an API call at plan time; the callback
only runs on keypress. No I/O at setup.

### Load-time I/O (the point of lazy loading)

Each lazy activation does: one `:packadd` (vim.cmd), one glob for the
pack directory (plan.lua), one glob for `after/plugin/**/*.{lua,vim}`
(post-startup only), and `require` of **explicitly declared** `module`
names — never derived from the source. This is deferred I/O by design.

### Compile-time micro-items (negligible, one-shot)

- `normalize_array`/`normalize_events`/`normalize_keys` allocate fresh
  tables even for already-array inputs
- DFS cycle detection is O(depth²) — fine for typical chains (< 5
  levels); a depth-limited hash set would fix deep graphs
- `CONSUMED_KEYS` passthrough filter iterates `pairs(spec)` per spec

### Rejected (design decisions)

- **async loading** (`vim.uv.spawn` around `vim.pack.add`): `vim.pack.add`
  guarantees synchronous install, so eager and trigger loads work even in
  a first session. Async would complicate startup ordering against the
  small-core principle; first-install blocking UX belongs to vim.pack.
- **dev auto-reload via file watching**: `reload_all()` invoked manually
  gives the same effect; watching adds process management, debouncing and
  recursion control for no gain. Three lines of `vim.uv.fs_event` in your
  own config do it if wanted.
- **perf regression tests in CI**: local thresholds risk flaking on CI
  machines; they stay in `tests/run.lua perf` (run locally).

## Open items

None. New hot paths must land with a perf regression test in
`tests/run.lua perf` (asserted thresholds) or a note here explaining
why the threshold doesn't apply.

## Benchmarks

Standalone benchmarks for manual profiling (not part of CI):

```sh
# Bash benchmark (cold/warm start + profile breakdown)
bash tests/benchmarks/bench.sh

# Lua micro-benchmark (μs scale, multiple sizes)
nvim --cmd "set rtp+=." -l tests/benchmarks/bench.lua

# laze.nvim only
nvim -u NONE --headless -l tests/benchmarks/compile_only.lua

# Fair comparison: laze.nvim vs lazy.nvim
nvim -u NONE --headless -l tests/benchmarks/compile_compare.lua
```
