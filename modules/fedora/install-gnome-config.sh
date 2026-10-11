#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="gnome-config"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

# === GNOME session check (clean still runs, to undo a previous install) ===
if [[ "$ACTION" != "clean" && "${XDG_CURRENT_DESKTOP:-}" != *GNOME* ]]; then
  echo "⏭️  GNOME not detected (XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-unset})"
  echo "   Skipping GNOME configuration."
  exit 0
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALLPAPER_SOURCE="$REPO_DIR/wallpapers/background.jpg"
WALLPAPER_DEST="$HOME_DIR/Pictures/background.jpg"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "Error: Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* ]]; then
  echo "Error: Unsupported OS: $ID (Fedora only)"
  exit 1
fi

# Packages and commands
DEPS_PKGS=(glib2)
DEPS_CMDS=(gsettings)

# === Dependency Installer ===
install_dependencies() {
  echo "Ensuring required dependencies..."
  sudo dnf install -y "${DEPS_PKGS[@]}"

  # Verify commands exist
  for cmd in "${DEPS_CMDS[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "$cmd is available."
    else
      echo "Error: $cmd not found after install."
      exit 1
    fi
  done
}

# === Wallpaper installer ===
install_config() {
  echo "Checking for wallpaper in: $WALLPAPER_SOURCE"

  if [[ ! -f "$WALLPAPER_SOURCE" ]]; then
    echo "Warning: Wallpaper not found: $WALLPAPER_SOURCE"
    echo "   Skipping wallpaper setup."
    return 0
  fi

  echo "Copying wallpaper to Pictures folder..."
  run_as_user mkdir -p "$HOME_DIR/Pictures"
  run_as_user install -m 0644 "$WALLPAPER_SOURCE" "$WALLPAPER_DEST"
  echo "Wallpaper copied to: $WALLPAPER_DEST"

  if command -v gsettings >/dev/null 2>&1; then
    echo "Setting wallpaper via gsettings..."
    run_as_user gsettings set org.gnome.desktop.background picture-uri "file://$WALLPAPER_DEST"
    run_as_user gsettings set org.gnome.desktop.background picture-uri-dark "file://$WALLPAPER_DEST"
    echo "Wallpaper set."
  else
    echo "Warning: gsettings not available. Set wallpaper manually."
  fi
}

# === GNOME Settings ===
configure_gnome() {
  if ! command -v gsettings >/dev/null 2>&1; then
    echo "Warning: gsettings not available. Skipping GNOME configuration."
    return 0
  fi

  echo "Applying GNOME settings..."

  # Dark theme preference
  run_as_user gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || true
  run_as_user gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark' || true

  # Window controls
  run_as_user gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close' || true

  # Disable animations (optional, for performance)
  # run_as_user gsettings set org.gnome.desktop.interface enable-animations false || true

  echo "GNOME settings applied."
}

# === Clean ===
# Settings applied by configure_gnome — reset to the GNOME defaults on clean
GSETTINGS_KEYS=(
  "org.gnome.desktop.interface color-scheme"
  "org.gnome.desktop.interface gtk-theme"
  "org.gnome.desktop.wm.preferences button-layout"
)

clean_config() {
  echo "Cleaning GNOME config..."

  if command -v gsettings >/dev/null 2>&1; then
    local entry key current
    for entry in "${GSETTINGS_KEYS[@]}"; do
      # shellcheck disable=SC2086  # "schema key" is split on purpose
      run_as_user gsettings reset $entry || true
    done
    # Only reset the wallpaper if it still points at the one we installed
    for key in picture-uri picture-uri-dark; do
      current="$(run_as_user gsettings get org.gnome.desktop.background "$key" 2>/dev/null || true)"
      if [[ "$current" == *"$WALLPAPER_DEST"* ]]; then
        run_as_user gsettings reset org.gnome.desktop.background "$key" || true
      fi
    done
    echo "GNOME settings reset to defaults."
  fi

  if [[ -f "$WALLPAPER_DEST" ]]; then
    run_as_user rm -f "$WALLPAPER_DEST"
    echo "Removed wallpaper."
  fi

  echo "Clean complete."
}

# === Entry Point ===
case "$ACTION" in
all)
  install_dependencies
  install_config
  configure_gnome
  ;;
deps)
  install_dependencies
  ;;
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
  die "Unknown action: $ACTION (use: all | deps | install | config | clean)"
  ;;
esac
