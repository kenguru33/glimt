#!/bin/bash
set -e

MODULE_NAME="jetbrains-toolbox"
ACTION="${1:-all}"

BASE_DIR="$HOME/.local/share/JetBrains/Toolbox"
BIN_PATH="$BASE_DIR/bin/jetbrains-toolbox"
TMP_DIR="/tmp/jetbrains-toolbox"
DESKTOP_FILE="$HOME/.local/share/applications/jetbrains-toolbox.desktop"

# === Detect OS ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Could not detect operating system."
  exit 1
fi

# === Dependencies ===
DEPS_DEBIAN=(curl jq tar libfuse2)
DEPS_FEDORA=(curl jq tar fuse)

install_deps() {
  echo "📦 Installing dependencies for $OS_ID..."
  if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" ]]; then
    sudo apt update
    sudo apt install -y "${DEPS_DEBIAN[@]}"
  elif [[ "$OS_ID" == "fedora" ]]; then
    sudo dnf install -y "${DEPS_FEDORA[@]}"
  else
    echo "❌ Unsupported OS: $OS_ID"
    exit 1
  fi
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

  # Wait a few seconds to let Toolbox move itself
  sleep 5

  if [[ ! -f "$BIN_PATH" ]]; then
    echo "⚠️ Toolbox binary not found at expected path: $BIN_PATH"
    echo "   It may take a few more seconds to finish first-run setup."
  fi

  log "🖥️ Creating desktop launcher..."
  mkdir -p "$(dirname "$DESKTOP_FILE")"

 ICON_PATH="$HOME/.local/share/JetBrains/Toolbox/.install-icon.svg"
  [[ ! -f "$ICON_PATH" ]] && ICON_PATH="/usr/share/pixmaps/jetbrains-toolbox.svg"

  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=JetBrains Toolbox
Comment=Manage your JetBrains IDEs
Exec=$BIN_PATH
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
  echo "    $BIN_PATH &"
}

clean_toolbox() {
  log "🧹 Removing JetBrains Toolbox..."
  rm -rf "$BASE_DIR"
  rm -f "$DESKTOP_FILE"
  update-desktop-database "$HOME/.local/share/applications" &>/dev/null || true
  log "✅ Removed JetBrains Toolbox and launcher."
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
