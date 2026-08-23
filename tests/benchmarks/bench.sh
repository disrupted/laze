#!/usr/bin/env bash
# Benchmark script for laze.nvim: cold/warm start + profile breakdown.

set -e

# Auto-detect the repo root (this script lives in tests/benchmarks/).
LAZE_DIR="${LAZE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
PLUGIN_DIR="${LAZE_PLUGINS:-/tmp/laze-plugins}"

if [ ! -d "$PLUGIN_DIR" ]; then
  echo "error: plugin dir not found: $PLUGIN_DIR" >&2
  echo "  clone real plugins first: ./tests/profile/setup.sh" >&2
  exit 1
fi

echo "=== laze.nvim benchmark ==="
echo "Testing with plugins: $(ls "$PLUGIN_DIR")"

# Test 1: Cold start (no cache)
echo ""
echo "--- Cold start (first run) ---"
for i in 1 2 3; do
  echo "Run $i:"
  (time -p nvim -u NONE --cmd "set rtp+=$LAZE_DIR" --headless \
    -c "lua require('laze').setup({
      {dir='$PLUGIN_DIR/plenary.nvim'},
      {dir='$PLUGIN_DIR/nui.nvim', ft='markdown'},
      {dir='$PLUGIN_DIR/which-key.nvim', event='VeryLazy', keys='<leader>wk'},
      {dir='$PLUGIN_DIR/oil.nvim', cmd='Oil', keys={{lhs='<leader>o', mode='n'}}},
    })" \
    -c "qa!" 2>&1) 2>&1 | grep -E "^(real|user|sys)"
done

# Test 2: Warm start (with cache)
echo ""
echo "--- Warm start (cached) ---"
for i in 1 2 3; do
  echo "Run $i:"
  (time -p nvim -u NONE --cmd "set rtp+=$LAZE_DIR" --headless \
    -c "lua require('laze').setup({
      {dir='$PLUGIN_DIR/plenary.nvim'},
      {dir='$PLUGIN_DIR/nui.nvim', ft='markdown'},
      {dir='$PLUGIN_DIR/which-key.nvim', event='VeryLazy', keys='<leader>wk'},
      {dir='$PLUGIN_DIR/oil.nvim', cmd='Oil', keys={{lhs='<leader>o', mode='n'}}},
    })" \
    -c "qa!" 2>&1) 2>&1 | grep -E "^(real|user|sys)"
done

# Test 3: Profile data
echo ""
echo "--- Profile breakdown ---"
nvim -u NONE --cmd "set rtp+=$LAZE_DIR" --headless \
  -c "lua local timings = {}; require('laze').setup({
    {dir='$PLUGIN_DIR/plenary.nvim'},
    {dir='$PLUGIN_DIR/nui.nvim', ft='markdown'},
    {dir='$PLUGIN_DIR/which-key.nvim', event='VeryLazy', keys='<leader>wk'},
    {dir='$PLUGIN_DIR/oil.nvim', cmd='Oil', keys={{lhs='<leader>o', mode='n'}}},
  }, {on_load=function(id, ms) table.insert(timings, {id=id, time_ms=ms}) end}); for _,t in ipairs(timings) do print(string.format('%6.2f %s', t.time_ms, t.id)) end; print(#timings .. ' plugins measured')" \
  -c "qa!" 2>&1 | grep -E "ms|measured"