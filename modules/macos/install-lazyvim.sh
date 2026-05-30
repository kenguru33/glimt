#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="lazyvim"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

TIMESTAMP="$(date +%Y%m%d%H%M%S)"
NVIM_DIRS=(
  "$HOME_DIR/.config/nvim"
  "$HOME_DIR/.local/share/nvim"
  "$HOME_DIR/.local/state/nvim"
  "$HOME_DIR/.cache/nvim"
)

deps() {
  log "Installing Neovim dependencies via Homebrew..."
  brew install neovim git curl ripgrep fd
}

install() {
  if [[ -e "$HOME_DIR/.config/nvim" ]]; then
    if [[ -t 0 && -t 1 ]] && command -v gum &>/dev/null; then
      gum confirm "~/.config/nvim already exists. Back it up and overwrite with LazyVim?" || {
        warn "Skipping LazyVim install — existing config left in place."
        return 0
      }
    elif [[ -t 0 && -t 1 ]]; then
      read -r -p "[lazyvim] ~/.config/nvim already exists. Overwrite? [y/N] " reply
      [[ "${reply,,}" == "y" ]] || { warn "Skipping LazyVim install."; return 0; }
    else
      warn "~/.config/nvim already exists — skipping in non-interactive mode."
      return 0
    fi
  fi

  log "Backing up existing Neovim config..."
  for dir in "${NVIM_DIRS[@]}"; do
    if [[ -e "$dir" ]]; then
      local backup="${dir}.bak-${TIMESTAMP}"
      mv "$dir" "$backup"
      log "Moved $dir → $backup"
    fi
  done

  log "Cloning LazyVim starter..."
  git clone https://github.com/LazyVim/starter "$HOME_DIR/.config/nvim"
  rm -rf "$HOME_DIR/.config/nvim/.git"
  log "✅ LazyVim installed. Run nvim and :Lazy sync"
}

config() {
  log "Adding Catppuccin theme plugin..."
  local plugin_dir="$HOME_DIR/.config/nvim/lua/plugins"
  mkdir -p "$plugin_dir"
  cat > "$plugin_dir/catppuccin.lua" <<'EOF'
return {
  "catppuccin/nvim",
  name = "catppuccin",
  priority = 1000,
  config = function()
    vim.cmd.colorscheme("catppuccin")
  end,
}
EOF
  log "✅ Catppuccin plugin added and set as default colorscheme."
}

clean() {
  log "Removing LazyVim configuration and data..."
  for dir in "${NVIM_DIRS[@]}"; do
    if [[ -e "$dir" ]]; then
      rm -rf "$dir"
      log "Removed $dir"
    fi
  done
}

restore() {
  log "Searching for latest backup to restore..."
  for dir in "${NVIM_DIRS[@]}"; do
    local latest_backup
    latest_backup=$(ls -d "${dir}.bak-"* 2>/dev/null | sort | tail -n1 || true)
    if [[ -n "$latest_backup" ]]; then
      [[ -e "$dir" ]] && rm -rf "$dir"
      mv "$latest_backup" "$dir"
      log "Restored $latest_backup → $dir"
    else
      warn "No backup found for $dir"
    fi
  done
}

case "$ACTION" in
  all)     deps; install; config ;;
  deps)    deps ;;
  install) install ;;
  config)  config ;;
  clean)   clean ;;
  restore) restore ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean|restore]"
    exit 1
    ;;
esac
