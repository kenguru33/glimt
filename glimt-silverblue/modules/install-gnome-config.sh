#!/bin/bash
set -e

MODULE_NAME="gnome-config"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALLPAPER_SOURCE="$REPO_DIR/wallpapers/background.jpg"
WALLPAPER_DEST="$HOME_DIR/Pictures/background.jpg"
ACTION="${1:-all}"

# === Wallpaper installer ===
install_config() {
  echo "📁 Checking for wallpaper in: $WALLPAPER_SOURCE"

  if [[ ! -f "$WALLPAPER_SOURCE" ]]; then
    echo "⚠️  Wallpaper not found: $WALLPAPER_SOURCE"
    echo "   Skipping wallpaper setup."
    return 0
  fi

  echo "📥 Copying wallpaper to Pictures folder..."
  sudo -u "$REAL_USER" mkdir -p "$HOME_DIR/Pictures"
  sudo -u "$REAL_USER" cp "$WALLPAPER_SOURCE" "$WALLPAPER_DEST"
  echo "✅ Wallpaper copied to: $WALLPAPER_DEST"

  if command -v gsettings >/dev/null 2>&1; then
    echo "🎨 Setting wallpaper via gsettings..."
    sudo -u "$REAL_USER" gsettings set org.gnome.desktop.background picture-uri "file://$WALLPAPER_DEST"
    sudo -u "$REAL_USER" gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALLPAPER_DEST"
    echo "✅ Wallpaper set."
  else
    echo "⚠️  gsettings not available. Set wallpaper manually."
  fi
}

# === GNOME Settings ===
configure_gnome() {
  if ! command -v gsettings >/dev/null 2>&1; then
    echo "⚠️  gsettings not available. Skipping GNOME configuration."
    return 0
  fi

  echo "⚙️  Applying GNOME settings..."

  # Dark theme preference
  sudo -u "$REAL_USER" gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
  sudo -u "$REAL_USER" gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || true

  # Window controls
  sudo -u "$REAL_USER" gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close' || true

  # Disable animations (optional, for performance)
  # sudo -u "$REAL_USER" gsettings set org.gnome.desktop.interface enable-animations false || true

  echo "✅ GNOME settings applied."
}

# === Clean ===
clean_config() {
  echo "🧹 Cleaning GNOME config..."

  if [[ -f "$WALLPAPER_DEST" ]]; then
    sudo -u "$REAL_USER" rm -f "$WALLPAPER_DEST"
    echo "✅ Removed wallpaper."
  fi

  echo "✅ Clean complete."
}

# === Entry Point ===
case "$ACTION" in
all)
  install_config
  configure_gnome
  ;;
deps) ;;
install)
  install_config
  configure_gnome
  ;;
config)
  configure_gnome
  ;;
clean)
  clean_config
  ;;
*)
  echo "❌ Unknown action: $ACTION"
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac
