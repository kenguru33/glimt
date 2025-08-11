#!/bin/bash
set -e
trap 'echo "❌ Something went wrong. Exiting." >&2' ERR

FONT_NAME="Hack Nerd Font"
FONT_DIR="$HOME/.local/share/fonts"
FONT_ZIP="/tmp/Hack.zip"
FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/Hack.zip"
ACTION="${1:-all}"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

# === Required packages ===
DEPS=("wget" "unzip" "fontconfig")

install_dependencies() {
  echo "🔧 Installing required dependencies..."

  if [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]]; then
    sudo apt update
    for dep in "${DEPS[@]}"; do
      if ! dpkg -l | grep -qw "$dep"; then
        echo "📦 Installing $dep..."
        sudo apt install -y "$dep"
      else
        echo "✅ $dep is already installed."
      fi
    done

  elif [[ "$ID" == "fedora" ]]; then
    for dep in "${DEPS[@]}"; do
      if ! rpm -q "$dep" &>/dev/null; then
        echo "📦 Installing $dep..."
        sudo dnf install -y "$dep"
      else
        echo "✅ $dep is already installed."
      fi
    done

  else
    echo "❌ Unsupported OS: $ID"
    exit 1
  fi
}

install_fonts() {
  echo "🔤 Installing $FONT_NAME..."

  if fc-list | grep -qi "Hack Nerd Font"; then
    echo "✅ $FONT_NAME already installed. Skipping."
    return
  fi

  mkdir -p "$FONT_DIR"
  wget -qO "$FONT_ZIP" "$FONT_URL"
  unzip -o "$FONT_ZIP" -d "$FONT_DIR"
  rm -f "$FONT_ZIP"
  fc-cache -fv > /dev/null

  echo "✅ $FONT_NAME installed and font cache refreshed."
}

configure_fonts() {
  echo "ℹ️ No configuration needed for $FONT_NAME."
}

clean_fonts() {
  echo "🧹 Removing $FONT_NAME..."
  rm -f "$FONT_DIR"/*Hack*
  fc-cache -fv > /dev/null
  echo "✅ Fonts removed and cache refreshed."
}

show_help() {
  echo "Usage: $0 [all|deps|install|config|clean]"
  echo ""
  echo "  all      Run deps + install + config"
  echo "  deps     Install required tools"
  echo "  install  Download and install $FONT_NAME"
  echo "  config   No-op (pattern consistency)"
  echo "  clean    Remove font and refresh font cache"
}

# === Entry Point ===
case "$ACTION" in
  all)
    install_dependencies
    install_fonts
    configure_fonts
    ;;
  deps)
    install_dependencies
    ;;
  install)
    install_fonts
    ;;
  config)
    configure_fonts
    ;;
  clean)
    clean_fonts
    ;;
  *)
    show_help
    ;;
esac
