# Design

## Output model

Laze produces a pure IR with three parts:

* `pack`: passed to `vim.pack.add()`
* `registry`: plugin metadata and callbacks
* `routes`: trigger indexes

The execution plan is then generated from that IR.
At load time, laze only requires module names explicitly declared via `module`. It never guesses the module from the repo name (`hrsh7th/cmp-buffer` ships the `cmp_buffer` module), and `config` functions do their own requires — mirroring lazy.nvim.

## When does a plugin's code run?

* **Eager** (no triggers, not a `dependencies` dep): the installed directory is added to the runtimepath at setup (`:packadd!`), so the startup `plugin/` and `after/plugin/` phases source its files exactly once. `init` (if any) and `config` run from the plan at setup time.
* **Lazy** (has a trigger, or is a `dependencies` dep of a lazy plugin): **nothing** runs at startup — the plugin is not even on the runtimepath. When its trigger fires after startup, the plan `:packadd`s it (sourcing `plugin/` and `ftdetect/`), sources its `after/plugin/` scripts, then runs `init` → `module` requires → `config`. If a trigger fires during startup, laze adds it to a closure-local pending queue and finalizes it at `VimEnter`; this avoids a lazy opt package being left on the runtimepath with its `plugin/` files unsourced.
* `dependencies` of a lazy plugin stay off the runtimepath too; they activate immediately before the parent.

### The activation invariant

Every plugin's `plugin/` and `after/plugin/` files are sourced **exactly once**, ordered by one rule:

> `vim_did_enter == 0` (during startup) → eager plugins use `:packadd!` only; startup-requested lazy plugins are finalized once at `VimEnter`.
> `vim_did_enter ~= 0` (after startup) → `:packadd` (sources `plugin/`, `ftdetect/`) + manually source the plugin's own `after/plugin/` files (`:packadd` never sources those — startup-only).

Breaking this invariant produces double-source (side effects run twice) or missing files. The startup-phase integration test in `tests/run.lua` asserts it by spawning real sessions; keep it green when touching activation.

Note: `:packadd` after startup also sources `ftdetect/`; during startup the runtime's filetype machinery picks it up from the runtimepath on demand.

## Notes

* `vim.loader.enable()` should be called early.
* `vim.pack` is responsible for placement / installation.
* Laze is responsible for timing and trigger wiring.
* The plugin itself is responsible for its own semantics.
* Dev paths with `~` are expanded at compile time via `vim.fn.expand`. Absolute and relative paths pass through verbatim.

## Philosophy

Laze is intentionally small.

It values:

* explicitness over magic
* pure transforms over stateful managers
* runtime simplicity over feature sprawl
* easy deletion over clever abstractions

---

Laze is a tiny compiler for lazy.nvim-like specs.

It keeps three things separate:

* user input
* pure compiled IR
* thin execution plan

That separation is the whole point.
