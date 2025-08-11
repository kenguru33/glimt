#!/bin/bash
set -e

MODULE_NAME="jetbrains-toolbox"
ACTION="${1:-all}"

BASE_DIR="$HOME/.local/share/JetBrains/Toolbox"
TMP_DIR="/tmp/jetbrains-toolbox"
DESKTOP_FILE="$HOME/.local/share/applications/jetbrains-toolbox.desktop"
SYMLINK="$HOME/.local/bin/jetbrains-toolbox"

# === Detect OS ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Could not detect operating system."
  exit 1
fi

if [[ "$OS_ID" != "debian" && "$OS_ID" != "ubuntu" ]]; then
  echo "❌ This script only supports Debian or Ubuntu."
  exit 1
fi

# === Dependencies ===
DEPS=(curl jq tar libfuse2)

install_deps() {
  echo "📦 Installing dependencies..."
  sudo apt update
  sudo apt install -y "${DEPS[@]}"
}

log() {
  echo -e "\n$1\n"
}

install_toolbox() {
  log "📦 Installing JetBrains Toolbox..."

  mkdir -p "$TMP_DIR"
  cd "$TMP_DIR"

  log "🌐 Fetching latest JetBrains Toolbox download URL..."
  URL=$(curl -fsSL "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" \
    | jq -r '.TBA[0].downloads.linux.link')

  if [[ -z "$URL" || "$URL" == "null" ]]; then
    echo "❌ Failed to fetch download URL."
    exit 1
  fi

  FILENAME="${URL##*/}"
  log "⬇️ Downloading: $FILENAME"
  curl -L "$URL" -o "$FILENAME"

  log "📁 Extracting to: $BASE_DIR"
  rm -rf "$BASE_DIR"
  mkdir -p "$BASE_DIR"
  tar -xzf "$FILENAME" --strip-components=1 -C "$BASE_DIR"

  log "🚀 Launching JetBrains Toolbox for first-time setup..."
  nohup "$BASE_DIR/jetbrains-toolbox" >/dev/null 2>&1 &

  sleep 5

  # Detect relocated binary (after first launch)
  if [[ -f "$BASE_DIR/bin/jetbrains-toolbox" ]]; then
    LAUNCHER_BIN_PATH="$BASE_DIR/bin/jetbrains-toolbox"
  else
    LAUNCHER_BIN_PATH="$BASE_DIR/jetbrains-toolbox"
    echo "⚠️ Toolbox may not have completed self-installation yet."
  fi

  log "🖥️ Creating desktop launcher..."
  mkdir -p "$(dirname "$DESKTOP_FILE")"
  ICON_PATH="$BASE_DIR/.install-icon.svg"

  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=JetBrains Toolbox
Comment=Manage your JetBrains IDEs
Exec=$LAUNCHER_BIN_PATH
Icon=$ICON_PATH
Terminal=false
Type=Application
Categories=Development;IDE;
StartupNotify=true
EOF

  chmod +x "$DESKTOP_FILE"
  update-desktop-database "$HOME/.local/share/applications" &>/dev/null || true

  log "✅ JetBrains Toolbox installed and launcher created."
  echo "📍 You can now find it in your app menu, or run:"
  echo "    $LAUNCHER_BIN_PATH &"

  log "🔗 Creating symlink in ~/.local/bin..."
  mkdir -p "$HOME/.local/bin"
  ln -sf "$LAUNCHER_BIN_PATH" "$SYMLINK"
  echo "💡 You can now run Toolbox from terminal with:"
  echo "    jetbrains-toolbox &"
}

clean_toolbox() {
  log "🧹 Removing JetBrains Toolbox..."
  rm -rf "$BASE_DIR"
  rm -f "$DESKTOP_FILE"
  rm -f "$SYMLINK"
  update-desktop-database "$HOME/.local/share/applications" &>/dev/null || true
  log "✅ Removed JetBrains Toolbox, launcher, and symlink."
}

# === Entry point ===
case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_toolbox
    ;;
  clean)
    clean_toolbox
    ;;
  all)
    install_deps
    install_toolbox
    ;;
  *)
    echo "Usage: $0 [deps|install|clean|all]"
    exit 1
    ;;
esac
