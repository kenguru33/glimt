#!/bin/bash
set -e
trap 'echo "❌ Bat install failed. Exiting." >&2' ERR

MODULE_NAME="bat"
ACTION="${1:-all}"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

BAT_THEME_NAME="Catppuccin Mocha"
BAT_BIN="$HOME_DIR/.local/bin/bat"
THEME_VARIANTS=(Latte Frappe Macchiato Mocha)
THEME_REPO_BASE="https://github.com/catppuccin/bat/raw/main/themes"

# === Detect OS ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Cannot detect operating system."
  exit 1
fi

# === Step: deps ===
install_deps() {
  if [[ "$OS_ID" != "debian" && "$OS_ID" != "ubuntu" ]]; then
    echo "❌ Unsupported OS: $OS_ID"
    exit 1
  fi

  echo "📦 Installing batcat and wget..."
  sudo apt update
  sudo apt install -y bat wget
}

# === Step: install ===
install_bat() {
  echo "🔗 Creating ~/.local/bin/bat → batcat symlink..."
  mkdir -p "$HOME_DIR/.local/bin"
  ln -sf "$(command -v batcat)" "$BAT_BIN"
  chown -R "$REAL_USER:$REAL_USER" "$HOME_DIR/.local"
}

# === Step: config ===
config_bat() {
  echo "🎨 Installing Catppuccin themes..."

  BAT_CONFIG_DIR="$($BAT_BIN --config-dir)"
  BAT_THEME_DIR="$BAT_CONFIG_DIR/themes"
  BAT_CONFIG_FILE="$BAT_CONFIG_DIR/config"

  mkdir -p "$BAT_THEME_DIR"

  for variant in "${THEME_VARIANTS[@]}"; do
    wget -q -O "$BAT_THEME_DIR/Catppuccin ${variant}.tmTheme" \
      "$THEME_REPO_BASE/Catppuccin%20${variant}.tmTheme"
  done

  echo "🧹 Rebuilding theme cache..."
  sudo -u "$REAL_USER" "$BAT_BIN" cache --build

  echo "⚙️ Setting default theme: $BAT_THEME_NAME"
  echo "--theme=\"$BAT_THEME_NAME\"" > "$BAT_CONFIG_FILE"
  chown -R "$REAL_USER:$REAL_USER" "$BAT_CONFIG_DIR"
}

# === Step: clean ===
clean_bat() {
  echo "🧹 Removing bat themes and config..."
  BAT_CONFIG_DIR="$($BAT_BIN --config-dir)"
  BAT_THEME_DIR="$BAT_CONFIG_DIR/themes"
  BAT_CONFIG_FILE="$BAT_CONFIG_DIR/config"
  BAT_CACHE_DIR="$HOME_DIR/.cache/bat"

  rm -rf "$BAT_THEME_DIR" "$BAT_CONFIG_FILE" "$BAT_CACHE_DIR"

  if [[ -L "$BAT_BIN" ]]; then
    echo "❌ Removing bat symlink"
    rm -f "$BAT_BIN"
  fi
}

# === Entry point ===
case "$ACTION" in
  all)     install_deps; install_bat; config_bat ;;
  deps)    install_deps ;;
  install) install_bat ;;
  config)  config_bat ;;
  clean)   clean_bat ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac
