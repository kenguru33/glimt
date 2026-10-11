#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="lazyvim"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATPPUCCIN_TEMPLATE="$SCRIPT_DIR/config/lazyvim-catppuccin.lua"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"
NVIM_DIRS=(
  "$HOME_DIR/.config/nvim"
  "$HOME_DIR/.local/share/nvim"
  "$HOME_DIR/.local/state/nvim"
  "$HOME_DIR/.cache/nvim"
)

# === Ensure Fedora-based OS ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
    echo "Error: This script supports only Fedora/RHEL-based systems."
    exit 1
  fi
else
  echo "Error: Cannot detect OS."
  exit 1
fi

# === Step: deps ===
install_dependencies() {
  echo "Installing Neovim and related tools..."
  sudo dnf install -y neovim git curl unzip ripgrep fd-find fzf gcc gcc-c++ make
  echo "Dependencies installed."
}

# === Step: install ===
install_lazyvim() {
  echo "Backing up any existing Neovim config..."
  for dir in "${NVIM_DIRS[@]}"; do
    if [[ -e "$dir" ]]; then
      backup="${dir}.bak-${TIMESTAMP}"
      sudo -u "$REAL_USER" mv "$dir" "$backup" 2>/dev/null || mv "$dir" "$backup"
      echo "Moved $dir → $backup"
    fi
  done

  echo "Cloning LazyVim starter..."
  sudo -u "$REAL_USER" sh -c "cd '$HOME_DIR' && git clone https://github.com/LazyVim/starter .config/nvim"
  sudo -u "$REAL_USER" rm -rf "$HOME_DIR/.config/nvim/.git"
  chown -R "$REAL_USER:$REAL_USER" "$HOME_DIR/.config/nvim"
  echo "LazyVim installed."
  echo "Start Neovim with 'nvim' and run :Lazy sync"
}

# === Step: config ===
config_lazyvim() {
  echo "Adding Catppuccin theme plugin..."
  PLUGIN_DIR="$HOME_DIR/.config/nvim/lua/plugins"
  sudo -u "$REAL_USER" mkdir -p "$PLUGIN_DIR"
  deploy_config "$CATPPUCCIN_TEMPLATE" "$PLUGIN_DIR/catppuccin.lua"
  echo "Catppuccin plugin added and set as default colorscheme."
}

# === Step: clean ===
clean_lazyvim() {
  echo "Removing LazyVim configuration and data..."
  for dir in "${NVIM_DIRS[@]}"; do
    if [[ -e "$dir" ]]; then
      sudo -u "$REAL_USER" rm -rf "$dir" 2>/dev/null || rm -rf "$dir"
      echo "Removed $dir"
    fi
  done
  echo "LazyVim configuration removed."

  # neovim belongs to install-nvim.sh and fzf/fd to install-fzf.sh; gcc/make
  # are a shared toolchain. ripgrep is the only package installed for LazyVim alone.
  if confirm "Uninstall ripgrep (installed for LazyVim)?"; then
    sudo dnf remove -y ripgrep
    echo "ripgrep removed."
  fi
}

# === Step: restore ===
restore_backup() {
  echo "Searching for latest backup to restore..."
  for dir in "${NVIM_DIRS[@]}"; do
    # Globs expand sorted, and the timestamp suffix sorts chronologically
    local backups=() b latest_backup=""
    for b in "${dir}.bak-"*; do
      [[ -e "$b" ]] && backups+=("$b")
    done
    (( ${#backups[@]} )) && latest_backup="${backups[${#backups[@]}-1]}"
    if [[ -n "$latest_backup" ]]; then
      echo "Restoring $latest_backup → $dir"
      if [[ -e "$dir" ]]; then
        sudo -u "$REAL_USER" rm -rf "$dir" 2>/dev/null || rm -rf "$dir"
      fi
      sudo -u "$REAL_USER" mv "$latest_backup" "$dir" 2>/dev/null || mv "$latest_backup" "$dir"
      chown -R "$REAL_USER:$REAL_USER" "$dir"
    else
      echo "Warning: No backup found for $dir"
    fi
  done
  echo "Backup restore complete."
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
    echo "[$MODULE_NAME] unknown action: $ACTION" >&2
    echo "Usage: $0 [all|deps|install|config|clean|restore]"
    exit 1
    ;;
esac

