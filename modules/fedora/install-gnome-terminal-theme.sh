#!/bin/bash
set -Eeuo pipefail

# === GNOME session check ===
if [[ "${XDG_CURRENT_DESKTOP:-}" != *GNOME* ]]; then
  echo "⏭️  GNOME not detected (XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-unset})"
  echo "   Skipping GNOME configuration."
  exit 0
fi

MODULE_NAME="gnome-terminal-theme"
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* ]]; then
  echo "❌ This script supports Fedora only."
  exit 1
fi

# === Dependencies ===
deps() {
  echo "📦 Checking dependencies..."
  if ! command -v gsettings >/dev/null 2>&1; then
    echo "⚠️  gsettings not available. GNOME may not be installed."
    return 0
  fi
  echo "✅ Dependencies satisfied."
}

# === Install theme ===
install() {
  echo "🎨 Configuring GNOME Terminal theme..."

  if ! command -v gsettings >/dev/null 2>&1; then
    echo "⚠️  gsettings not available. Skipping terminal theme."
    return 0
  fi

  # Set Catppuccin Mocha theme (dark theme)
  PROFILE=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")

  # Background color (Catppuccin Mocha base)
  gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${PROFILE}/" background-color '#1e1e2e' || true
  gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${PROFILE}/" foreground-color '#cdd6f4' || true

  # Use custom colors
  gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${PROFILE}/" use-theme-colors false || true

  # Font
  gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${PROFILE}/" font 'JetBrains Mono Nerd Font 12' || true

  echo "✅ GNOME Terminal theme configured."
}

# === Config ===
config() {
  echo "✅ Theme configuration complete."
}

# === Clean ===
clean() {
  echo "🧹 Resetting GNOME Terminal theme..."

  if ! command -v gsettings >/dev/null 2>&1; then
    echo "⚠️  gsettings not available."
    return 0
  fi

  PROFILE=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")
  gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${PROFILE}/" use-theme-colors true || true

  echo "✅ Terminal theme reset."
}

# === Entry Point ===
case "$ACTION" in
all)
  deps
  install
  config
  ;;
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
*)
  echo "❌ Unknown action: $ACTION"
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac
