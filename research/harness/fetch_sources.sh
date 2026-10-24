#!/usr/bin/env bash
# Shallow-clone every external source used by the research harness into data/.
# Idempotent: existing clones are left alone. Run from anywhere.
set -euo pipefail
DATA="$(cd "$(dirname "$0")/../data" && pwd)"
cd "$DATA"

clone() { # clone <owner/repo> <dest> [sparse paths...]
  local repo=$1 dest=$2; shift 2
  [ -d "$dest" ] && return 0
  if [ $# -gt 0 ]; then
    git clone -q --depth 1 --filter=blob:none --sparse "https://github.com/$repo" "$dest"
    git -C "$dest" sparse-checkout set "$@"
  else
    git clone -q --depth 1 "https://github.com/$repo" "$dest"
  fi
}

# --- palettes (Job A)
clone tinted-theming/schemes schemes
clone mbadolato/iTerm2-Color-Schemes iterm2 windowsterminal

# --- highlight queries (Job B)
clone nvim-treesitter/nvim-treesitter nvim-treesitter
clone Wilfred/tree-sitter-elisp tree-sitter-elisp   # nvim-treesitter has no elisp queries

# --- code corpus (Job B)
mkdir -p corpus
for r in psf/requests pallets/flask \
         expressjs/express axios/axios \
         colinhacks/zod sindresorhus/ky \
         BurntSushi/ripgrep sharkdp/bat \
         spf13/cobra gin-gonic/gin \
         valkey-io/valkey libuv/libuv \
         nvim-telescope/telescope.nvim \
         nvm-sh/nvm Bash-it/bash-it \
         magit/magit company-mode/company-mode \
         google/gson apache/commons-lang; do
  clone "$r" "corpus/${r//\//_}"
done
clone neovim/neovim corpus/neovim_neovim runtime/lua
