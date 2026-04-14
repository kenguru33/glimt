#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Btop install failed. Exiting." >&2' ERR

MODULE_NAME="btop"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

# === Resolve Real User and Home ===
if ! id "$REAL_USER" &>/dev/null; then
  echo "❌ Could not resolve real user: $REAL_USER"
  exit 1
fi

BTOP_CONFIG_DIR="$HOME_DIR/.config/btop"
BTOP_THEME_DIR="$BTOP_CONFIG_DIR/themes"
BTOP_CONFIG_FILE="$BTOP_CONFIG_DIR/btop.conf"
CATPPUCCIN_THEME_URL="https://raw.githubusercontent.com/catppuccin/btop/main/themes/catppuccin_mocha.theme"

# === OS Check ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "❌ This installer only supports Fedora/RHEL."
  exit 1
fi

# === Step: deps ===
install_deps() {
  echo "📦 Installing required packages..."
  sudo dnf install -y btop wget
}

# === Step: install ===
install_btop() {
  echo "✅ btop installed via dnf (or already present)."
}

# === Step: config ===
config_btop() {
  echo "🎨 Applying Catppuccin Mocha theme to btop..."

  sudo -u "$REAL_USER" mkdir -p "$BTOP_THEME_DIR"
  echo "⬇️  Downloading Catppuccin Mocha theme..."
  sudo -u "$REAL_USER" wget -qO "$BTOP_THEME_DIR/catppuccin_mocha.theme" "$CATPPUCCIN_THEME_URL"

  echo "🛠 Ensuring btop config exists..."
  sudo -u "$REAL_USER" mkdir -p "$BTOP_CONFIG_DIR"

  if [[ ! -f "$BTOP_CONFIG_FILE" ]]; then
    echo "🧪 Attempting to generate config using btop..."
    sudo -u "$REAL_USER" env TERM=xterm-256color btop --write-config </dev/null >/dev/null 2>&1 || {
      echo "⚠️ btop --write-config failed. Creating minimal config manually."
      sudo -u "$REAL_USER" bash -c "echo 'color_theme = \"catppuccin_mocha\"' > \"$BTOP_CONFIG_FILE\""
    }
  fi

  echo "🎯 Setting color_theme to catppuccin_mocha..."
  if sudo -u "$REAL_USER" grep -q '^color_theme' "$BTOP_CONFIG_FILE" 2>/dev/null; then
    sudo -u "$REAL_USER" sed -i 's/^color_theme.*/color_theme = "catppuccin_mocha"/' "$BTOP_CONFIG_FILE"
  else
    sudo -u "$REAL_USER" bash -c "echo 'color_theme = \"catppuccin_mocha\"' >> \"$BTOP_CONFIG_FILE\""
  fi

  sudo chown -R "$REAL_USER:$REAL_USER" "$BTOP_CONFIG_DIR"
  echo "✅ Theme set to catppuccin_mocha in $BTOP_CONFIG_FILE"
}

# === Step: clean ===
clean_btop() {
  echo "🧹 Removing btop config and theme..."
  sudo -u "$REAL_USER" rm -f "$BTOP_THEME_DIR/catppuccin_mocha.theme" 2>/dev/null || true
  sudo -u "$REAL_USER" rm -f "$BTOP_CONFIG_FILE" 2>/dev/null || true
  echo "✅ btop theme and config removed."
}

# === Entry Point ===
case "$ACTION" in
  all)     install_deps; install_btop; config_btop ;;
  deps)    install_deps ;;
  install) install_btop ;;
  config)  config_btop ;;
  clean)   clean_btop ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

