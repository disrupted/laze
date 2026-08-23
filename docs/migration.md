# Migrating from lazy.nvim

laze accepts lazy.nvim's declarative spec shape on purpose (escape hatch first). Most configs port with mechanical edits, and the conformance test `tests/test_subset.lua` pins the subset continuously. What to expect per field:

**Works as-is** — `[1]`/`src`, `dir`, `url`, `name`, `dev`, `dev_path`, `event`, `ft`, `cmd`, `keys`, `init`, `config`, `cond`, `enabled`, `dependencies`, `build`, `branch`/`tag`/`commit`, `pin`, `module` (laze's take on it, see below).

**One-line conversions**

* `opts = {...}` → `config = function() require("X").setup({...}) end`. laze rejects `opts` with a warning. The common `{ "X", opts = {} }` pattern is explicitly out of scope.
* `config = true` (lazy's "call require(X).setup(opts)") → the same explicit function. laze errors on `config = true`.
* `lazy = true` → remove it. In laze, *no trigger* means eager and a trigger means lazy — there is no separate `lazy` flag.
* `import = "..."` → not supported; load your spec files yourself and pass the resulting tables to `setup`.
* `priority` → **honored for eager ordering** (higher first, tie-break: id), default 50 — matches lazy.nvim's colorscheme-first workflow. Non-number priorities are rejected.
* `submodules`, `optional`, `specs`, `main`: consumed with a per-compile warning (each compile, not one-time), no equivalent.

**Rejected loudly (safe direction — lazy.nvim never breaks a laze config, only the reverse)**

* Function-shaped triggers (`event`/`cmd`/`ft`/`keys` as a function): compile error — laze does not evaluate triggers.
* `build` as a list of commands (lazy.nvim's array form): compile error — use a single string or function. (`build = false` is accepted and means "no build", like lazy.nvim.)

**Silently degraded**

* `keys` entries keep `lhs`/`rhs`/`mode`/`desc`/`silent`; other `vim.keymap.set` options (`noremap`, `nowait`, `expr`, `callback`, `buffer`, …) are dropped.
* `module = "name"` in laze is an *opt-in* require trigger (registered as a `package.preload` entry); lazy.nvim's `module = false` is an *opt-out* of automatic require-loading. `module = false` in laze means "no module triggers".
* `version = "*"` and semver strings work (mapped to `vim.pack`'s `version`); `branch`/`tag`/`commit` are folded into the same field. lazy.nvim's `version = false` semantics (run the update resolver differently) do not apply — nil here.
* `after` is a laze extension for dep ordering (lazy.nvim's equivalent: `dependencies`). lazy.nvim silently ignores it — convert to `dependencies` when moving back.