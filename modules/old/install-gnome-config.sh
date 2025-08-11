#!/bin/bash
set -e

MODULE_NAME="gnome-config"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALLPAPER_SOURCE="$REPO_DIR/wallpapers/background.jpg"
WALLPAPER_DEST="$HOME/Pictures/background.jpg"
ACTION="${1:-all}"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

# === Set DEPS based on distro ===
if [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]]; then
  DEPS=(libglib2.0-bin gsettings)
  INSTALL_CMD="sudo apt install -y"
  UPDATE_CMD="sudo apt update"
elif [[ "$ID" == "fedora" ]]; then
  DEPS=(glib2 gsettings)
  INSTALL_CMD="sudo dnf install -y"
  UPDATE_CMD="sudo dnf check-update || true"
else
  echo "❌ Unsupported OS: $ID"
  exit 1
fi

# === Dependency Installer ===
install_dependencies() {
  echo "🔧 Checking required dependencies..."
  $UPDATE_CMD

  for dep in "${DEPS[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      echo "📦 Installing $dep..."
      $INSTALL_CMD "$dep"
    else
      echo "✅ $dep is already installed."
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
