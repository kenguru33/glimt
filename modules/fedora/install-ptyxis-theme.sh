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
  echo "📦 Ensuring Ptyxis, curl, and git are installed (Fedora)..."
  sudo dnf makecache -y
  sudo dnf install -y ptyxis curl git
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

  # Try alternative system locations
  for alt_path in "/usr/share/ptyxis" "/usr/lib/ptyxis" "/usr/libexec/ptyxis"; do
    if [[ -f "${alt_path}/palettes/${PALETTE_NAME}.json" ]]; then
      echo "📋 Copying palette from ${alt_path}..."
      sudo -u "$REAL_USER" cp "${alt_path}/palettes/${PALETTE_NAME}.json" "$PALETTE_FILE"
      chown "$REAL_USER:$REAL_USER" "$PALETTE_FILE"
      echo "✅ Catppuccin Mocha palette installed for Ptyxis."
      return 0
    fi
  done

  # Fallback: Try to clone repository and get palette file
  echo "⬇️  Attempting to get palette from Ptyxis repository..."
  TMP_DIR=$(mktemp -d)
  if sudo -u "$REAL_USER" git clone --depth=1 https://gitlab.gnome.org/chergert/ptyxis.git "$TMP_DIR" 2>/dev/null; then
    REPO_PALETTE="$TMP_DIR/src/palettes/${PALETTE_NAME}.json"
    if [[ -f "$REPO_PALETTE" ]]; then
      echo "📋 Copying palette from repository..."
      sudo -u "$REAL_USER" cp "$REPO_PALETTE" "$PALETTE_FILE"
      chown "$REAL_USER:$REAL_USER" "$PALETTE_FILE"
      rm -rf "$TMP_DIR"
      echo "✅ Catppuccin Mocha palette installed for Ptyxis."
      return 0
    fi
  fi
  rm -rf "$TMP_DIR"

  # Final fallback: Create palette file with Catppuccin Mocha colors
  echo "📝 Creating Catppuccin Mocha palette file from standard colors..."
  sudo -u "$REAL_USER" cat > "$PALETTE_FILE" <<'EOF'
{
  "name": "Catppuccin Mocha",
  "colors": {
    "background": "#1e1e2e",
    "foreground": "#cdd6f4",
    "cursor": "#f5e0dc",
    "selection": "#585b70",
    "black": "#45475a",
    "red": "#f38ba8",
    "green": "#a6e3a1",
    "yellow": "#f9e2af",
    "blue": "#89b4fa",
    "magenta": "#f5c2e7",
    "cyan": "#94e2d5",
    "white": "#bac2de",
    "bright_black": "#585b70",
    "bright_red": "#f38ba8",
    "bright_green": "#a6e3a1",
    "bright_yellow": "#f9e2af",
    "bright_blue": "#89b4fa",
    "bright_magenta": "#f5c2e7",
    "bright_cyan": "#94e2d5",
    "bright_white": "#a6adc8"
  }
}
EOF
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


