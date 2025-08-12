#!/bin/bash
set -e
trap 'echo "❌ An error occurred. Exiting." >&2' ERR

MODULE_NAME="lazyvim"
ACTION="${1:-all}"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
NVIM_DIRS=(~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim)

# === Ensure Debian-based OS ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  if [[ "$ID" != "debian" && "$ID_LIKE" != *"debian"* ]]; then
    echo "❌ This script supports only Debian-based systems."
    exit 1
  fi
else
  echo "❌ Cannot detect OS."
  exit 1
fi

# === Step: deps ===
install_dependencies() {
  echo "📦 Installing Neovim and related tools..."
  sudo apt update
  sudo apt install -y neovim git curl unzip ripgrep fd-find fzf build-essential
  echo "✅ Dependencies installed."
}

# === Step: install ===
install_lazyvim() {
  echo "📁 Backing up any existing Neovim config..."
  for dir in "${NVIM_DIRS[@]}"; do
    expanded_dir="$(eval echo "$dir")"
    if [[ -e "$expanded_dir" ]]; then
      backup="${expanded_dir}.bak-${TIMESTAMP}"
      mv "$expanded_dir" "$backup"
      echo "🔄 Moved $expanded_dir → $backup"
    fi
  done

  echo "📥 Cloning LazyVim starter..."
  git clone https://github.com/LazyVim/starter ~/.config/nvim
  rm -rf ~/.config/nvim/.git
  echo "✅ LazyVim installed."
  echo "🚀 Start Neovim with 'nvim' and run :Lazy sync"
}

# === Step: config ===
config_lazyvim() {
  echo "🎨 Adding Catppuccin theme plugin..."
  mkdir -p ~/.config/nvim/lua/plugins
  cat > ~/.config/nvim/lua/plugins/catppuccin.lua <<'EOF'
return {
  "catppuccin/nvim",
  name = "catppuccin",
  priority = 1000,
  config = function()
    vim.cmd.colorscheme("catppuccin")
  end,
}
EOF
  echo "✅ Catppuccin plugin added and set as default colorscheme."
}

# === Step: clean ===
clean_lazyvim() {
  echo "🧹 Removing LazyVim configuration and data..."
  for dir in "${NVIM_DIRS[@]}"; do
    rm -rf "$(eval echo "$dir")"
  done
  echo "✅ LazyVim configuration removed."

  echo "📦 Optionally remove Neovim and tools..."
  read -rp "Uninstall Neovim and related tools? [y/N]: " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    sudo apt purge -y neovim ripgrep fd-find fzf
    sudo apt autoremove -y
    echo "✅ Packages removed."
  fi
}

# === Step: restore ===
restore_backup() {
  echo "📂 Searching for latest backup to restore..."
  for dir in "${NVIM_DIRS[@]}"; do
    expanded_dir="$(eval echo "$dir")"
    latest_backup=$(ls -d "${expanded_dir}.bak-"* 2>/dev/null | sort | tail -n1)
    if [[ -n "$latest_backup" ]]; then
      echo "🔁 Restoring $latest_backup → $expanded_dir"
      rm -rf "$expanded_dir"
      mv "$latest_backup" "$expanded_dir"
    else
      echo "⚠️ No backup found for $expanded_dir"
    fi
  done
  echo "✅ Backup restore complete."
}

# === Dispatcher ===
case "$ACTION" in
  deps)    install_dependencies ;;
  install) install_lazyvim ;;
  config)  config_lazyvim ;;
  clean)   clean_lazyvim ;;
  restore) restore_backup ;;
  all)     install_dependencies; install_lazyvim; config_lazyvim ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean|restore]"
    exit 1
    ;;
esac
