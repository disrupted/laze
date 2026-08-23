#!/usr/bin/env bash
# Setup: clone real plugins to /tmp/laze-plugins/ for testing
set -e

PLUGIN_DIR="/tmp/laze-plugins"
mkdir -p "$PLUGIN_DIR"

echo "==> Cloning plugins to $PLUGIN_DIR ..."

clone_if_missing() {
  local repo="$1"
  local name="${repo##*/}"
  if [ ! -d "$PLUGIN_DIR/$name" ]; then
    git clone --depth=1 "https://github.com/$repo" "$PLUGIN_DIR/$name"
  else
    echo "  $name already exists, skipping"
  fi
}

clone_if_missing "nvim-lua/plenary.nvim"       # utility, no trigger (start plugin)
clone_if_missing "MunifTanjim/nui.nvim"         # UI lib, ft=markdown
clone_if_missing "folke/which-key.nvim"          # VeryLazy + keys
clone_if_missing "stevearc/oil.nvim"             # cmd = "Oil"
clone_if_missing "nvim-tree/nvim-web-devicons"   # start plugin, colorscheme dependency

echo "==> Done. Run: ./tests/profile/run.sh"
