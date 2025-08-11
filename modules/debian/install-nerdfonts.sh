#!/bin/bash
set -e
trap 'echo "❌ Nerd Font install failed. Exiting." >&2' ERR

ACTION="${1:-all}"
FONT_DIR="$HOME/.local/share/fonts"
TMP_DIR="/tmp/nerdfonts"
FONT_CACHE_LOG="/tmp/fc-cache.log"

# === Font definitions ===
declare -A FONTS
FONTS=(
  ["Hack"]="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/Hack.zip"
  ["FiraCode"]="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/FiraCode.zip"
  ["JetBrainsMono"]="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip"
)

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS."
  exit 1
fi

if [[ "$ID" != "debian" && "$ID_LIKE" != *"debian"* ]]; then
  echo "❌ This script supports Debian only."
  exit 1
fi

# === Dependencies ===
DEPS=("wget" "unzip" "fontconfig")

install_deps() {
  echo "📦 Installing required APT packages..."
  sudo apt update
  for dep in "${DEPS[@]}"; do
    if ! dpkg -l | grep -qw "$dep"; then
      echo "➡️  Installing $dep..."
      sudo apt install -y "$dep"
    else
      echo "✅ $dep is already installed."
    fi
  done
}

install_fonts() {
  echo "🔤 Installing Nerd Fonts to $FONT_DIR..."
  mkdir -p "$FONT_DIR" "$TMP_DIR"

  for name in "${!FONTS[@]}"; do
    if fc-list | grep -qi "$name Nerd Font"; then
      echo "✅ $name Nerd Font already installed. Skipping."
      continue
    fi

    zip_path="$TMP_DIR/${name}.zip"
    echo "⬇️  Downloading $name Nerd Font..."
    wget -q -O "$zip_path" "${FONTS[$name]}"

    echo "📦 Extracting $name..."
    unzip -o "$zip_path" -d "$FONT_DIR" >/dev/null
    rm -f "$zip_path"
  done

  echo "🔄 Rebuilding font cache..."
  fc-cache -fv > "$FONT_CACHE_LOG"
  echo "✅ Font cache rebuilt."
}

configure_fonts() {
  echo "ℹ️ No configuration needed. Fonts are available to apps that support them."
}

clean_fonts() {
  echo "🧹 Removing installed Nerd Fonts..."

  for name in "${!FONTS[@]}"; do
    rm -f "$FONT_DIR"/*"$name"*
  done

  echo "🔄 Rebuilding font cache..."
  fc-cache -fv > "$FONT_CACHE_LOG"
  echo "✅ Fonts removed and font cache refreshed."
}

show_help() {
  echo "Usage: $0 [all|deps|install|config|clean]"
  echo ""
  echo "  all      Run deps + install + config"
  echo "  deps     Install required packages"
  echo "  install  Download and install Nerd Fonts"
  echo "  config   No-op (kept for structure)"
  echo "  clean    Remove installed fonts and refresh cache"
}

# === Entry Point ===
case "$ACTION" in
  all)     install_deps; install_fonts; configure_fonts ;;
  deps)    install_deps ;;
  install) install_fonts ;;
  config)  configure_fonts ;;
  clean)   clean_fonts ;;
  *)       show_help ;;
esac