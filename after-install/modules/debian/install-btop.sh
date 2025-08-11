#!/bin/bash
set -e
trap 'echo "❌ Btop install failed. Exiting." >&2' ERR

MODULE_NAME="btop"
ACTION="${1:-all}"

# === Resolve Real User and Home ===
REAL_USER="${SUDO_USER:-$USER}"

if ! id "$REAL_USER" &>/dev/null; then
  echo "❌ Could not resolve real user: $REAL_USER"
  exit 1
fi

HOME_DIR="$(eval echo "~$REAL_USER")"
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

if [[ "$ID" != "debian" && "$ID_LIKE" != *"debian"* ]]; then
  echo "❌ This installer only supports Debian."
  exit 1
fi

# === Step: deps ===
install_deps() {
  echo "📦 Installing required packages..."
  sudo apt update
  sudo apt install -y btop wget
}

# === Step: install ===
install_btop() {
  echo "✅ btop installed via apt (or already present)."
}

# === Step: config ===
config_btop() {
  echo "🎨 Applying Catppuccin Mocha theme to btop..."

  mkdir -p "$BTOP_THEME_DIR"
  echo "⬇️  Downloading Catppuccin Mocha theme..."
  wget -qO "$BTOP_THEME_DIR/catppuccin_mocha.theme" "$CATPPUCCIN_THEME_URL"

  echo "🛠 Ensuring btop config exists..."
  mkdir -p "$BTOP_CONFIG_DIR"

  if [[ ! -f "$BTOP_CONFIG_FILE" ]]; then
    echo "🧪 Attempting to generate config using btop..."
    sudo -u "$REAL_USER" env TERM=xterm-256color btop --write-config </dev/null >/dev/null 2>&1 || {
      echo "⚠️ btop --write-config failed. Creating minimal config manually."
      echo 'color_theme = "catppuccin_mocha"' > "$BTOP_CONFIG_FILE"
    }
  fi

  echo "🎯 Setting color_theme to catppuccin_mocha..."
  if grep -q '^color_theme' "$BTOP_CONFIG_FILE"; then
    sed -i 's/^color_theme.*/color_theme = "catppuccin_mocha"/' "$BTOP_CONFIG_FILE"
  else
    echo 'color_theme = "catppuccin_mocha"' >> "$BTOP_CONFIG_FILE"
  fi

  sudo chown -R "$REAL_USER:$REAL_USER" "$BTOP_CONFIG_DIR"
  echo "✅ Theme set to catppuccin_mocha in $BTOP_CONFIG_FILE"
}

# === Step: clean ===
clean_btop() {
  echo "🧹 Removing btop config and theme..."
  rm -f "$BTOP_THEME_DIR/catppuccin_mocha.theme"
  rm -f "$BTOP_CONFIG_FILE"
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
