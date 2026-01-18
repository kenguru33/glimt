#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ gnome-config failed at line $LINENO" >&2' ERR

MODULE_NAME="gnome-config"
ACTION="${1:-all}"

# --------------------------------------------------
# Resolve real user
# --------------------------------------------------
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

# --------------------------------------------------
# Resolve repo root (modules/ → repo/)
# --------------------------------------------------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
MODULES_DIR="$(dirname "$SCRIPT_PATH")"
REPO_ROOT="$(dirname "$MODULES_DIR")"

WALLPAPER_SOURCE="$REPO_ROOT/wallpapers/background.jpg"
WALLPAPER_DEST="$HOME_DIR/Pictures/background.jpg"

log() { echo "[$MODULE_NAME] $*"; }

# --------------------------------------------------
# GNOME guard
# --------------------------------------------------
is_gnome() {
  [[ "${XDG_CURRENT_DESKTOP:-}" == "GNOME" ]] \
    || [[ "${DESKTOP_SESSION:-}" == "gnome" ]] \
    || command -v gnome-shell >/dev/null 2>&1
}

if ! is_gnome; then
  log "Not running GNOME desktop – exiting early"
  exit 0
fi

# Must be run inside a GNOME session
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  log "No GNOME session bus detected – exiting early"
  exit 0
fi


# --------------------------------------------------
# Wallpaper installer
# --------------------------------------------------
install_config() {
  log "Checking for wallpaper: $WALLPAPER_SOURCE"

  if [[ ! -f "$WALLPAPER_SOURCE" ]]; then
    log "Wallpaper not found, skipping"
    return 0
  fi

  sudo -u "$REAL_USER" mkdir -p "$HOME_DIR/Pictures"
  sudo -u "$REAL_USER" cp "$WALLPAPER_SOURCE" "$WALLPAPER_DEST"

  log "Wallpaper copied to $WALLPAPER_DEST"

  if command -v gsettings >/dev/null 2>&1; then
    sudo -u "$REAL_USER" gsettings set \
      org.gnome.desktop.background picture-uri "file://$WALLPAPER_DEST" || true

    sudo -u "$REAL_USER" gsettings set \
      org.gnome.desktop.background picture-uri-dark "file://$WALLPAPER_DEST" || true

    log "Wallpaper applied via gsettings"
  else
    log "gsettings not available, skipping wallpaper apply"
  fi
}

# --------------------------------------------------
# GNOME preferences
# --------------------------------------------------
configure_gnome() {
  command -v gsettings >/dev/null 2>&1 || {
    log "gsettings not available, skipping GNOME config"
    return 0
  }

  log "Applying GNOME settings"

  sudo -u "$REAL_USER" gsettings set \
    org.gnome.desktop.interface color-scheme 'prefer-dark' || true

  sudo -u "$REAL_USER" gsettings set \
    org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || true

  sudo -u "$REAL_USER" gsettings set \
    org.gnome.desktop.wm.preferences button-layout \
    'appmenu:minimize,maximize,close' || true

  log "GNOME settings applied"
}

# --------------------------------------------------
# Clean
# --------------------------------------------------
clean_config() {
  log "Cleaning GNOME config"

  if [[ -f "$WALLPAPER_DEST" ]]; then
    sudo -u "$REAL_USER" rm -f "$WALLPAPER_DEST"
    log "Wallpaper removed"
  fi

  log "Clean complete"
}

# --------------------------------------------------
# Entry point
# --------------------------------------------------
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
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac

exit 0
