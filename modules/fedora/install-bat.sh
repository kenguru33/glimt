#!/bin/bash
set -e
trap 'echo "❌ Bat install failed. Exiting." >&2' ERR

MODULE_NAME="bat"
ACTION="${1:-all}"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

BAT_THEME_NAME="Catppuccin Mocha"
BAT_BIN="bat"  # On Fedora, bat is already called "bat" (not "batcat")
THEME_VARIANTS=(Latte Frappe Macchiato Mocha)
THEME_REPO_BASE="https://github.com/catppuccin/bat/raw/main/themes"

# === OS Check (Fedora only) ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "❌ This module supports Fedora/RHEL-based systems only."
  exit 1
fi

# === Step: deps ===
install_deps() {
  echo "📦 Installing bat and wget..."
  sudo dnf makecache -y
  sudo dnf install -y bat wget
}

# === Step: install ===
install_bat() {
  echo "✅ Bat is installed via DNF (no symlink needed on Fedora)"
  
  if ! command -v bat >/dev/null 2>&1; then
    echo "❌ bat command not found. Installing..."
    install_deps
  fi
  
  echo "✅ Bat is ready: $(command -v bat)"
}

# === Step: config ===
config_bat() {
  echo "🎨 Installing Catppuccin themes..."

  if ! command -v bat >/dev/null 2>&1; then
    echo "❌ bat command not found. Run 'install' first."
    exit 1
  fi

  BAT_CONFIG_DIR="$(sudo -u "$REAL_USER" bat --config-dir)"
  BAT_THEME_DIR="$BAT_CONFIG_DIR/themes"
  BAT_CONFIG_FILE="$BAT_CONFIG_DIR/config"

  sudo -u "$REAL_USER" mkdir -p "$BAT_THEME_DIR"

  # Use curl if available (more reliable), otherwise fall back to wget
  for variant in "${THEME_VARIANTS[@]}"; do
    local theme_file="$BAT_THEME_DIR/Catppuccin ${variant}.tmTheme"
    local theme_url="$THEME_REPO_BASE/Catppuccin%20${variant}.tmTheme"
    
    if command -v curl >/dev/null 2>&1; then
      sudo -u "$REAL_USER" curl -fsSL -o "$theme_file" "$theme_url" || {
        echo "⚠️  Failed to download Catppuccin ${variant} theme"
        continue
      }
    elif command -v wget >/dev/null 2>&1; then
      sudo -u "$REAL_USER" wget --quiet --output-document="$theme_file" "$theme_url" || {
        echo "⚠️  Failed to download Catppuccin ${variant} theme"
        continue
      }
    else
      echo "❌ Neither curl nor wget found. Cannot download themes."
      exit 1
    fi
  done

  echo "🧹 Rebuilding theme cache..."
  sudo -u "$REAL_USER" bat cache --build || {
    echo "⚠️  Failed to rebuild theme cache (themes may still work)"
  }

  echo "⚙️ Setting default theme: $BAT_THEME_NAME"
  sudo -u "$REAL_USER" sh -c "echo '--theme=\"$BAT_THEME_NAME\"' > '$BAT_CONFIG_FILE'"
  chown -R "$REAL_USER:$REAL_USER" "$BAT_CONFIG_DIR"
  
  echo "✅ Catppuccin themes installed successfully"
}

# === Step: clean ===
clean_bat() {
  echo "🧹 Removing bat themes and config..."
  BAT_CONFIG_DIR="$(sudo -u "$REAL_USER" bat --config-dir 2>/dev/null || echo "$HOME_DIR/.config/bat")"
  BAT_THEME_DIR="$BAT_CONFIG_DIR/themes"
  BAT_CONFIG_FILE="$BAT_CONFIG_DIR/config"
  BAT_CACHE_DIR="$HOME_DIR/.cache/bat"

  sudo -u "$REAL_USER" rm -rf "$BAT_THEME_DIR" "$BAT_CONFIG_FILE" "$BAT_CACHE_DIR"

  echo "✅ Bat config and themes removed."
  echo "ℹ️  To remove bat package: sudo dnf remove -y bat"
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


