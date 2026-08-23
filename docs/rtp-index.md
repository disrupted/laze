# Runtimepath index for the startup fast path

Status: adopted 2026-08. Scope: `plan.lua` activation fast path only. No IR,
API, or activation-semantics change.

## Background

During startup (`vim_did_enter == 0`), `load_plugin` skips plugin discovery
when the plugin's opt directory is already on `'runtimepath'` (the
`active_pack_dir` fast path — see the earlier resolved entry in
[performance.md](performance.md); setup()'s `vim.pack.add(..., { load = false })`
has just activated every eager plugin, so the follow-up glob + `:packadd!`
would be redundant).

That check ran **per plugin**: one `nvim_list_runtime_paths()` call (which
allocates a fresh Lua array holding every rtp entry) plus a linear scan over
all entries with a pattern match each.

Cost model: `O(E × R)` where `E` = plugins hitting the fast path (eager
plugins, plus rare startup-time trigger loads) and `R` = `'runtimepath`
length. Measured with a headless micro-benchmark (best-of-200, JIT-warmed):

```
rtp entries: 33, fast-path lookups: 15   (realistic small config)
current (per-plugin list + scan):  110.6 us
indexed (one list + one pass):       9.7 us
```

## Design

* `build_rtp_index(data_dir)` walks the runtimepath **once** and returns
  `{ [pkg]: dir }`, keeping the lexicographically-first directory per pkg —
  the same tie-break the discovery glob's sorted output produces, so a hit
  and a glob hit always agree.
* The map is held in a **closure-local** `rtp_index` inside `build_plan`,
  built lazily on the first fast-path lookup. Closure-locality is deliberate
  and matches `loaded`: `reload_all()` rebuilds the plan, so a rebuilt plan
  gets a fresh cache by construction — no cross-reload staleness is possible.
* Invalidation: `rtp_index = nil` at both runtimepath mutation sites owned by
  plan.lua — the local-dir `rtp:prepend` and the successful fallback
  `:packadd!`. These are the only mutation sites in the module, so the
  invariant ("any rtp mutation nils the cache") is enforceable within one
  file.
* A lookup miss keeps the existing glob + `:packadd` fallback verbatim.

## Correctness analysis

| Event                              | Effect                                                        |
| ---------------------------------- | ------------------------------------------------------------- |
| Cache miss                         | Safe: full glob + `:packadd` fallback runs (unchanged path)    |
| External code adds a pack dir      | Miss → fallback discovers it                                  |
| External code removes a pack dir   | Stale hit possible; requires third-party config removing a `site/pack/*/opt/*` directory from `'runtimepath'` mid-startup — no known actor |
| `reload_all()`                     | Fresh plan closure ⇒ fresh cache                               |

The activation invariant is untouched: hits skip exactly what they skipped
before; only *how* the presence check is answered changed. The
spawned-session startup-phase test in `tests/run.lua` pins this.

## Pros / Cons

Pros:

* ~0.1 ms per startup at realistic scale, and the win grows with config size
  (`O(E × R)` → `O(R + E)`).
* Removes `E` array allocations and `E × R` string comparisons from the
  hottest startup window.
* Zero API/IR/behavior change; identical rtp end state (asserted by the
  integration suite).

Cons:

* Adds one piece of cache state to correctness-critical loader code, guarded
  by a documented invariant rather than by querying fresh state each time.
* The stale-hit edge case above becomes theoretically reachable where the
  previous always-fresh query could never answer wrongly.
* ~15 lines more code and two comments to maintain.

## Alternatives considered

* **Do nothing, document accepted** — defensible at ~0.1 ms; rejected because
  the fix is small, local, its invariant is enforceable in one file, and the
  repo already adopts fixes of this size (e.g. the 90 µs compile hoist).
* **Module-level cache** (à la `installed_preloads`) — rejected: a rebuilt
  plan could inherit a stale map. Closure-locality removes the entire class.
* **Cache the raw entry list only** — still `O(E × R)` scans; saves only the
  repeated API calls, not the dominant cost.

## References

* Prior art: "plan.lua: redundant glob + `:packadd!` for already-active
  plugins" in [performance.md](performance.md) (introduced the fast path).
* Benchmark harness: headless script comparing both strategies at
  `R = 33`, `E = 15` (numbers above are best-of-200 after JIT warmup).
