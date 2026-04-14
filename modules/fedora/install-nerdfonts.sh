#!/bin/bash
set -Eeuo pipefail

MODULE_NAME="nerdfonts"
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

GLIMT_VERSIONS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../versions.env"
# shellcheck source=../../versions.env
source "$GLIMT_VERSIONS"

ACTION="${1:-all}"
FONT_DIR="$HOME_DIR/.local/share/fonts"
TMP_DIR="/tmp/nerdfonts"
FONT_CACHE_LOG="/tmp/fc-cache.log"

# === Font definitions ===
declare -A FONTS
FONTS=(
  ["Hack"]="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERDFONTS_VERSION}/Hack.zip"
  ["FiraCode"]="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERDFONTS_VERSION}/FiraCode.zip"
  ["JetBrainsMono"]="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERDFONTS_VERSION}/JetBrainsMono.zip"
)

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
DEPS=("wget" "unzip" "fontconfig")

install_deps() {
  echo "📦 Installing required DNF packages..."
  for dep in "${DEPS[@]}"; do
    if ! rpm -q "$dep" &>/dev/null; then
      echo "➡️  Installing $dep..."
      sudo dnf install -y "$dep"
    else
      echo "✅ $dep is already installed."
    fi
  done
}

install_fonts() {
  echo "🔤 Installing Nerd Fonts to $FONT_DIR..."
  run_as_user mkdir -p "$FONT_DIR" "$TMP_DIR"

  for name in "${!FONTS[@]}"; do
    if fc-list | grep -qi "$name Nerd Font"; then
      echo "✅ $name Nerd Font already installed. Skipping."
      continue
    fi

    zip_path="$TMP_DIR/${name}.zip"
    echo "⬇️  Downloading $name Nerd Font..."
    wget -q -O "$zip_path" "${FONTS[$name]}"

    echo "📦 Extracting $name..."
    run_as_user unzip -o "$zip_path" -d "$FONT_DIR" >/dev/null
    rm -f "$zip_path"
  done

  echo "🔄 Rebuilding font cache..."
  run_as_user fc-cache -fv > "$FONT_CACHE_LOG"
  echo "✅ Font cache rebuilt."
  verify_binary fc-list
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
  echo "✅ Clean complete."
}

# === Entry Point ===
case "$ACTION" in
  all)
    install_deps
    install_fonts
    configure_fonts
    ;;
  deps)
    install_deps
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
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

