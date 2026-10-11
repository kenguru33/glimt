#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="nerdfonts"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

GLIMT_VERSIONS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../versions.env"
# shellcheck source=../../versions.env
source "$GLIMT_VERSIONS"

FONT_DIR="$HOME_DIR/.local/share/fonts"
# Each font family is unzipped into its own directory below this one, so
# clean can remove exactly what was installed (incl. README/LICENSE files)
NERDFONTS_DIR="$FONT_DIR/NerdFonts"

# === Font definitions ===
declare -A FONTS=(
  ["Hack"]="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERDFONTS_VERSION}/Hack.zip"
  ["FiraCode"]="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERDFONTS_VERSION}/FiraCode.zip"
  ["JetBrainsMono"]="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERDFONTS_VERSION}/JetBrainsMono.zip"
)

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "Error: Cannot detect OS."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* ]]; then
  echo "Error: This script supports Fedora only."
  exit 1
fi

# === Dependencies ===
DEPS=("wget" "unzip" "fontconfig")

install_deps() {
  echo "Installing required DNF packages..."
  for dep in "${DEPS[@]}"; do
    if ! rpm -q "$dep" &>/dev/null; then
      echo "Installing $dep..."
      sudo dnf install -y "$dep"
    else
      echo "$dep is already installed."
    fi
  done
}

install_fonts() {
  echo "Installing Nerd Fonts to $NERDFONTS_DIR..."
  run_as_user mkdir -p "$NERDFONTS_DIR"

  # Private, user-owned download dir (downloads and unzip run as the user)
  local tmp_dir
  tmp_dir="$(run_as_user mktemp -d)"
  [[ -d "$tmp_dir" ]] || die "Could not create a temporary download directory"

  for name in "${!FONTS[@]}"; do
    # grep -q would exit early and SIGPIPE fc-list, failing the pipe under pipefail
    if fc-list | grep -i "$name Nerd Font" >/dev/null; then
      echo "$name Nerd Font already installed. Skipping."
      continue
    fi

    zip_path="$tmp_dir/${name}.zip"
    echo "⬇️  Downloading $name Nerd Font..."
    if ! run_as_user wget -q -O "$zip_path" "${FONTS[$name]}"; then
      run_as_user rm -rf "$tmp_dir"
      die "Download failed: ${FONTS[$name]}"
    fi

    echo "Extracting $name..."
    run_as_user mkdir -p "$NERDFONTS_DIR/$name"
    run_as_user unzip -o "$zip_path" -d "$NERDFONTS_DIR/$name" >/dev/null
    run_as_user rm -f "$zip_path"
  done
  run_as_user rm -rf "$tmp_dir"

  echo "Rebuilding font cache..."
  run_as_user fc-cache -f >/dev/null
  echo "Font cache rebuilt."
  verify_binary fc-list
}

configure_fonts() {
  echo "ℹ️ No configuration needed. Fonts are available to apps that support them."
}

clean_fonts() {
  echo "Removing installed Nerd Fonts..."

  local name f legacy
  for name in "${!FONTS[@]}"; do
    run_as_user rm -rf "${NERDFONTS_DIR:?}/${name:?}"

    # Legacy layout: older versions unzipped straight into $FONT_DIR. Only
    # the font files themselves are recognisable (<name>NerdFont*, plus the
    # JetBrainsMono "NL" variant); loose README/LICENSE files are left alone.
    legacy=()
    for f in "$FONT_DIR/${name}NerdFont"* "$FONT_DIR/${name}NLNerdFont"*; do
      [[ -f "$f" ]] && legacy+=("$f")
    done
    if (( ${#legacy[@]} )); then
      run_as_user rm -f "${legacy[@]}"
    fi
  done
  run_as_user rmdir "$NERDFONTS_DIR" 2>/dev/null || true

  echo "Rebuilding font cache..."
  run_as_user fc-cache -f >/dev/null 2>&1 || true
  echo "Clean complete."
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
    echo "[$MODULE_NAME] unknown action: $ACTION" >&2
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

