#!/usr/bin/env bash
set -euo pipefail

# Configuration
UUID="clipboard-history@alexsaveau.dev"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
TARGET="$EXT_DIR/$UUID"
REPO="https://github.com/SUPERCILEX/gnome-clipboard-history.git"

echo "📋 Installing GNOME Clipboard History Extension"

# Ensure gettext is available
if ! command -v msgfmt &>/dev/null; then
  echo "🔧 'msgfmt' not found. Installing gettext..."
  if command -v apt &>/dev/null; then
    sudo apt update && sudo apt install -y gettext
  else
    echo "❌ Unsupported package manager. Please install gettext manually."
    exit 1
  fi
fi

# Ensure gnome-extensions CLI is available
if ! command -v gnome-extensions &>/dev/null; then
  echo "❌ 'gnome-extensions' CLI not found. Please install it first."
  echo "On Debian/Ubuntu: sudo apt install gnome-shell-extension-prefs"
  exit 1
fi

# Create extension directory if it doesn't exist
mkdir -p "$EXT_DIR"

# Clone or update the repo
if [ -d "$TARGET" ]; then
  echo "🔄 Updating existing extension..."
  git -C "$TARGET" pull --ff-only
else
  echo "⬇️ Cloning extension to $TARGET..."
  git clone "$REPO" "$TARGET"
fi

# Build extension
echo "🛠️ Building extension..."
cd "$TARGET"
make

# Enable extension
echo "✅ Enabling extension..."
gnome-extensions enable "$UUID" || {
  echo "⚠️ Could not enable extension automatically. You may need to restart GNOME Shell or log out and back in."
}

# Reload GNOME Shell (only on X11)
if [ "${XDG_SESSION_TYPE:-}" = "x11" ]; then
  echo "🔄 Reloading GNOME Shell..."
  busctl --user call org.gnome.Shell /org/gnome/Shell org.gnome.Shell Eval s 'Meta.restart("")' || true
else
  echo "ℹ️ On Wayland, please log out and back in to activate the extension."
fi

echo "🎉 GNOME Clipboard History installed and enabled."
