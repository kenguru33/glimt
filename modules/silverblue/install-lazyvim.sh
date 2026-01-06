#!/bin/bash
set -e
trap 'echo "❌ An error occurred. Exiting." >&2' ERR

MODULE_NAME="lazyvim"
ACTION="${1:-all}"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
NVIM_DIRS=(
  "$HOME_DIR/.config/nvim"
  "$HOME_DIR/.local/share/nvim"
  "$HOME_DIR/.local/state/nvim"
  "$HOME_DIR/.cache/nvim"
)

# === Step: install ===
install_lazyvim() {
  echo "📁 Backing up any existing Neovim config..."
  for dir in "${NVIM_DIRS[@]}"; do
    if [[ -e "$dir" ]]; then
      backup="${dir}.bak-${TIMESTAMP}"
      sudo -u "$REAL_USER" mv "$dir" "$backup" 2>/dev/null || mv "$dir" "$backup"
      echo "🔄 Moved $dir → $backup"
    fi
  done

  echo "📥 Cloning LazyVim starter..."
  sudo -u "$REAL_USER" sh -c "cd '$HOME_DIR' && git clone https://github.com/LazyVim/starter .config/nvim"
  sudo -u "$REAL_USER" rm -rf "$HOME_DIR/.config/nvim/.git"
  chown -R "$REAL_USER:$REAL_USER" "$HOME_DIR/.config/nvim"
  echo "✅ LazyVim installed."
  echo "🚀 Start Neovim with 'nvim' and run :Lazy sync"
}

# === Step: config ===
config_lazyvim() {
  echo "🎨 Adding Catppuccin theme plugin..."
  PLUGIN_DIR="$HOME_DIR/.config/nvim/lua/plugins"
  sudo -u "$REAL_USER" mkdir -p "$PLUGIN_DIR"
  cat <<'EOF' | sudo -u "$REAL_USER" tee "$PLUGIN_DIR/catppuccin.lua" >/dev/null
return {
  "catppuccin/nvim",
  name = "catppuccin",
  priority = 1000,
  config = function()
    vim.cmd.colorscheme("catppuccin")
  end,
}
EOF
  chown "$REAL_USER:$REAL_USER" "$PLUGIN_DIR/catppuccin.lua"
  echo "✅ Catppuccin plugin added and set as default colorscheme."
}

# === Step: clean ===
clean_lazyvim() {
  echo "🧹 Removing LazyVim configuration and data..."
  for dir in "${NVIM_DIRS[@]}"; do
    if [[ -e "$dir" ]]; then
      sudo -u "$REAL_USER" rm -rf "$dir" 2>/dev/null || rm -rf "$dir"
      echo "🗑️  Removed $dir"
    fi
  done
  echo "✅ LazyVim configuration removed."

  echo "📦 Optionally remove Neovim and tools..."
  read -rp "Uninstall Neovim and related tools? [y/N]: " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    sudo dnf remove -y neovim ripgrep fd fzf
    echo "✅ Packages removed."
  fi
}

# === Step: restore ===
restore_backup() {
  echo "📂 Searching for latest backup to restore..."
  for dir in "${NVIM_DIRS[@]}"; do
    latest_backup=$(ls -d "${dir}.bak-"* 2>/dev/null | sort | tail -n1)
    if [[ -n "$latest_backup" ]]; then
      echo "🔁 Restoring $latest_backup → $dir"
      if [[ -e "$dir" ]]; then
        sudo -u "$REAL_USER" rm -rf "$dir" 2>/dev/null || rm -rf "$dir"
      fi
      sudo -u "$REAL_USER" mv "$latest_backup" "$dir" 2>/dev/null || mv "$latest_backup" "$dir"
      chown -R "$REAL_USER:$REAL_USER" "$dir"
    else
      echo "⚠️ No backup found for $dir"
    fi
  done
  echo "✅ Backup restore complete."
}

# === Dispatcher ===
case "$ACTION" in
deps) ;;
install)
  install_lazyvim
  ;;
config)
  config_lazyvim
  ;;
clean)
  clean_lazyvim
  ;;
restore)
  restore_backup
  ;;
all)
  install_lazyvim
  config_lazyvim
  ;;
*)
  echo "❌ Unknown action: $ACTION"
  echo "Usage: $0 [all|deps|install|config|clean|restore]"
  exit 1
  ;;
esac
