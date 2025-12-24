#!/bin/bash
set -e
trap 'echo "❌ Ptyxis Catppuccin theme setup failed. Exiting." >&2' ERR

MODULE_NAME="ptyxis-theme"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
PALETTE_DIR="$HOME_DIR/.config/ptyxis/palettes"
PALETTE_NAME="catppuccin-mocha"
PALETTE_FILE="$PALETTE_DIR/${PALETTE_NAME}.json"
PALETTE_URL="https://gitlab.gnome.org/chergert/ptyxis/-/raw/main/src/palettes/${PALETTE_NAME}.json"

# === Step: deps ===
deps() {
  echo "📦 Ensuring Ptyxis and curl are installed (Fedora)..."
  sudo dnf makecache -y
  sudo dnf install -y ptyxis curl
}

# === Step: install ===
install() {
  echo "🎨 Installing Catppuccin Mocha palette for Ptyxis..."

  # Ensure palette directory exists and is owned by the real user
  sudo -u "$REAL_USER" mkdir -p "$PALETTE_DIR"

  if [[ -f "$PALETTE_FILE" ]]; then
    echo "ℹ️ Palette already present at: $PALETTE_FILE"
    return 0
  fi

  # Try to find palette in system installation first
  SYSTEM_PALETTE="/usr/share/ptyxis/palettes/${PALETTE_NAME}.json"
  if [[ -f "$SYSTEM_PALETTE" ]]; then
    echo "📋 Copying palette from system installation..."
    sudo -u "$REAL_USER" cp "$SYSTEM_PALETTE" "$PALETTE_FILE"
    chown "$REAL_USER:$REAL_USER" "$PALETTE_FILE"
    echo "✅ Catppuccin Mocha palette installed for Ptyxis."
    return 0
  fi

  # Fallback: Download from upstream
  echo "⬇️  Downloading palette from upstream Ptyxis repository..."
  if ! sudo -u "$REAL_USER" curl -fsSL "$PALETTE_URL" -o "$PALETTE_FILE"; then
    echo "❌ Failed to download palette from: $PALETTE_URL"
    echo "   Attempted to download from GitLab, but the file may have moved."
    echo "   You can manually download the palette from:"
    echo "   https://gitlab.gnome.org/chergert/ptyxis"
    exit 1
  fi
  chown "$REAL_USER:$REAL_USER" "$PALETTE_FILE"

  echo "✅ Catppuccin Mocha palette installed for Ptyxis."
}

# === Step: config ===
config() {
  echo "📝 Ptyxis does not expose a stable CLI for theme selection."
  echo "ℹ️ To use the Catppuccin Mocha palette:"
  echo "   1) Open Ptyxis."
  echo "   2) Go to Preferences / Appearance (or Palette settings)."
  echo "   3) Select the \"Catppuccin Mocha\" palette."
}

# === Step: clean ===
clean() {
  echo "🧹 Removing Catppuccin Mocha palette for Ptyxis..."
  rm -f "$PALETTE_FILE"
  echo "✅ Removed: $PALETTE_FILE (Ptyxis package was left installed)."
}

# === Entry Point ===
case "$ACTION" in
  all)    deps; install; config ;;
  deps)   deps ;;
  install) install ;;
  config) config ;;
  clean)  clean ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac


