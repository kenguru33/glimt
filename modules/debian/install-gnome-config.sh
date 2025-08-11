#!/bin/bash
set -e

MODULE_NAME="gnome-config"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALLPAPER_SOURCE="$REPO_DIR/wallpapers/background.jpg"
WALLPAPER_DEST="$HOME/Pictures/background.jpg"
ACTION="${1:-all}"

# === OS Detection (Debian only) ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "debian" && "$ID_LIKE" != *"debian"* ]]; then
  echo "❌ Unsupported OS: $ID (Debian only)"
  exit 1
fi

# === APT helpers ===
UPDATE_CMD="sudo apt update"
INSTALL_CMD="sudo apt install -y"

# Packages and commands
DEPS_PKGS=(libglib2.0-bin)
DEPS_CMDS=(gsettings)

# === Dependency Installer ===
install_dependencies() {
  echo "🔧 Ensuring required dependencies..."
  $UPDATE_CMD
  $INSTALL_CMD "${DEPS_PKGS[@]}"

  # Verify commands exist
  for cmd in "${DEPS_CMDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "✅ $cmd is available."
    else
      echo "❌ $cmd not found after install."
      exit 1
    fi
  done
}

# === Wallpaper installer ===
install_config() {
  echo "📁 Checking for wallpaper in: $WALLPAPER_SOURCE"

  if [[ ! -f "$WALLPAPER_SOURCE" ]]; then
    echo "❌ Wallpaper not found: $WALLPAPER_SOURCE"
    exit 1
  fi

  echo "📥 Copying wallpaper to Pictures folder..."
  mkdir -p "$HOME/Pictures"
  cp "$WALLPAPER_SOURCE" "$WALLPAPER_DEST"
  echo "✅ Wallpaper copied to: $WALLPAPER_DEST"
}

# === GNOME configuration ===
config_gnome() {
  echo "🎨 Configuring GNOME settings..."

  gsettings set org.gnome.desktop.background picture-uri "file://$WALLPAPER_DEST"
  gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALLPAPER_DEST"
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close'

  echo "✅ GNOME configuration applied."
}

# === Reset ===
clean_config() {
  echo "🧹 Resetting GNOME settings..."

  gsettings reset org.gnome.desktop.background picture-uri
  gsettings reset org.gnome.desktop.background picture-uri-dark
  gsettings reset org.gnome.desktop.interface color-scheme
  gsettings reset org.gnome.desktop.wm.preferences button-layout

  if [[ -f "$WALLPAPER_DEST" ]]; then
    echo "🗑️  Removing copied wallpaper from Pictures..."
    rm -f "$WALLPAPER_DEST"
  fi

  echo "✅ GNOME settings reset."
}

# === Help ===
show_help() {
  echo "Usage: $0 {all|deps|install|config|clean}"
  echo ""
  echo "  all      Run deps + install + config"
  echo "  deps     Install required tools"
  echo "  install  Copy wallpaper"
  echo "  config   Apply GNOME settings"
  echo "  clean    Reset GNOME settings and remove wallpaper"
}

# === Entry point ===
case "$ACTION" in
  all)
    install_dependencies
    install_config
    config_gnome
    ;;
  deps)
    install_dependencies
    ;;
  install)
    install_config
    ;;
  config)
    config_gnome
    ;;
  clean)
    clean_config
    ;;
  *)
    show_help
    exit 1
    ;;
esac
