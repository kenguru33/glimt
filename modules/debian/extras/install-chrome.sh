#!/bin/bash
set -e

MODULE_NAME="google-chrome"
ACTION="${1:-all}"
RECONFIGURE=false
DEB_PATH="/tmp/google-chrome-stable.deb"

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
DEPS=(curl wget gnupg apt-transport-https desktop-file-utils)

install_deps() {
  echo "📦 Installing dependencies..."
  sudo apt update
  sudo apt install -y "${DEPS[@]}"
}

install_chrome() {
  echo "⬇️  Downloading Google Chrome .deb..."
  curl -fsSL -o "$DEB_PATH" https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

  echo "📦 Installing Google Chrome..."
  sudo apt install -y "$DEB_PATH"

  echo "✅ Google Chrome installed."
}

config_chrome() {
  echo "⚙️  Configuring Chrome for Wayland and NVIDIA..."

  local DESKTOP_FILE="$HOME/.local/share/applications/google-chrome-wayland.desktop"
  local OVERRIDE_FILE="$HOME/.local/share/applications/google-chrome.desktop"
  local SYSTEM_DESKTOP="/usr/share/applications/google-chrome.desktop"
  local WMCLASS="google-chrome-wayland"
  local CHROME_BIN="/opt/google/chrome/chrome"

  mkdir -p "$HOME/.local/share/applications"

  # Detect NVIDIA
  local HAS_NVIDIA=false
  if lspci | grep -i nvidia &>/dev/null; then
    HAS_NVIDIA=true
    echo "⚠️  NVIDIA GPU detected — enabling __GLX_VENDOR_LIBRARY_NAME=nvidia"
  fi

  # Compose Exec line
  local EXEC_LINE
  if [[ "$HAS_NVIDIA" == true ]]; then
    EXEC_LINE="env __GLX_VENDOR_LIBRARY_NAME=nvidia $CHROME_BIN --ozone-platform=wayland --class=$WMCLASS %U"
  else
    EXEC_LINE="$CHROME_BIN --ozone-platform=wayland --class=$WMCLASS %U"
  fi

  if [[ "$RECONFIGURE" = true || ! -f "$DESKTOP_FILE" ]]; then
    echo "🖼 Writing launcher: $DESKTOP_FILE"
    cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=Google Chrome (Wayland)
GenericName=Web Browser
Comment=Web browser optimized for Wayland
Type=Application
Exec=$EXEC_LINE
Icon=google-chrome
Terminal=false
StartupNotify=false
StartupWMClass=$WMCLASS
Categories=Network;WebBrowser;
EOF
  else
    echo "✅ Launcher already exists."
  fi

  if [[ "$RECONFIGURE" = true || ! -f "$OVERRIDE_FILE" ]]; then
    if [[ -f "$SYSTEM_DESKTOP" ]]; then
      echo "🙈 Hiding system launcher: $OVERRIDE_FILE"
      echo "[Desktop Entry]
Hidden=true" > "$OVERRIDE_FILE"
    fi
  else
    echo "✅ Default launcher already hidden."
  fi

  echo "🔃 Updating desktop database..."
  update-desktop-database "$HOME/.local/share/applications"

  echo "✅ Chrome is configured for Wayland with no dock icon delay."
  echo "📌 Launch 'Google Chrome (Wayland)' from search and pin to dock."
}

clean_chrome() {
  echo "🧹 Uninstalling Google Chrome..."
  sudo apt remove -y google-chrome-stable || true
  sudo apt autoremove -y
  rm -f "$DEB_PATH"
  rm -f "$HOME/.local/share/applications/google-chrome.desktop"
  rm -f "$HOME/.local/share/applications/google-chrome-wayland.desktop"
  update-desktop-database "$HOME/.local/share/applications" || true
  echo "✅ Chrome uninstalled and cleaned."
}

# === Main entry point ===
if [[ "$2" == "--reconfigure" ]]; then
  RECONFIGURE=true
fi

case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_chrome
    ;;
  config)
    config_chrome
    ;;
  clean)
    clean_chrome
    ;;
  all)
    install_deps
    install_chrome
    config_chrome
    ;;
  *)
    echo "Usage: $0 {deps|install|config|clean|all} [--reconfigure]"
    exit 1
    ;;
esac
