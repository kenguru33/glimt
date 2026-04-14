#!/usr/bin/env bash
# Glimt module: jetbrains-toolbox
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="jetbrains-toolbox"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"

BASE_DIR="$HOME_DIR/.local/share/JetBrains/Toolbox"
TMP_DIR="/tmp/jetbrains-toolbox"
DESKTOP_FILE="$HOME_DIR/.local/share/applications/jetbrains-toolbox.desktop"
SYMLINK="$HOME_DIR/.local/bin/jetbrains-toolbox"

# === Resolve icon path and write desktop entry ===
# Usage: _write_desktop_file <launcher_bin_path>
_write_desktop_file() {
  local launcher_bin_path="$1"
  local icons_dir="$HOME_DIR/.local/share/icons"
  local icon_path=""

  for candidate in \
      "$BASE_DIR/.install-icon.svg" \
      "$BASE_DIR/icon.svg" \
      "$BASE_DIR/jetbrains-toolbox.svg" \
      "$icons_dir/jetbrains-toolbox.svg"; do
    if [[ -f "$candidate" ]]; then
      icon_path="$candidate"
      break
    fi
  done

  if [[ -n "$icon_path" && "$icon_path" != "$icons_dir/jetbrains-toolbox.svg" ]]; then
    mkdir -p "$icons_dir"
    cp -f "$icon_path" "$icons_dir/jetbrains-toolbox.svg" 2>/dev/null || true
    icon_path="$icons_dir/jetbrains-toolbox.svg"
    log "✅ Icon copied to: $icon_path"
  elif [[ -z "$icon_path" ]]; then
    log "⚠️  Icon not found, using default"
    icon_path="jetbrains-toolbox"
  fi

  mkdir -p "$(dirname "$DESKTOP_FILE")"
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Name=JetBrains Toolbox
Comment=Manage your JetBrains IDEs
Exec=$launcher_bin_path
Icon=$icon_path
Terminal=false
Type=Application
Categories=Development;IDE;
StartupNotify=true
EOF
  chmod +x "$DESKTOP_FILE"
  update-desktop-database "$HOME_DIR/.local/share/applications" &>/dev/null || true
  log "✅ Desktop launcher created"
}

# === OS Check ===
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  log "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* ]]; then
  log "❌ This script supports Fedora-based systems only."
  exit 1
fi

deps() {
  log "📦 Checking dependencies..."
  # curl, jq, tar, and fuse are available by default in Silverblue
  log "✅ No additional dependencies required"
}

install_toolbox() {
  require_user

  log "📦 Installing JetBrains Toolbox..."

  if [[ -d "$BASE_DIR" && -x "$BASE_DIR/jetbrains-toolbox" ]] || [[ -f "$BASE_DIR/bin/jetbrains-toolbox" ]]; then
    log "✅ JetBrains Toolbox already installed"
    return 0
  fi

  mkdir -p "$TMP_DIR"
  cd "$TMP_DIR"

  log "🌐 Fetching latest JetBrains Toolbox download URL..."
  local url
  url=$(curl -fsSL "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" \
    | jq -r '.TBA[0].downloads.linux.link')

  if [[ -z "$url" || "$url" == "null" ]]; then
    log "❌ Failed to fetch download URL"
    exit 1
  fi

  local filename="${url##*/}"
  log "⬇️  Downloading: $filename"
  curl -L "$url" -o "$filename"

  log "📁 Extracting to: $BASE_DIR"
  rm -rf "$BASE_DIR"
  mkdir -p "$BASE_DIR"
  tar -xzf "$filename" --strip-components=1 -C "$BASE_DIR"

  log "🚀 Launching JetBrains Toolbox for first-time setup..."
  nohup "$BASE_DIR/jetbrains-toolbox" >/dev/null 2>&1 &

  sleep 5

  # Detect relocated binary (after first launch)
  local launcher_bin_path
  if [[ -f "$BASE_DIR/bin/jetbrains-toolbox" ]]; then
    launcher_bin_path="$BASE_DIR/bin/jetbrains-toolbox"
  else
    launcher_bin_path="$BASE_DIR/jetbrains-toolbox"
    log "⚠️  Toolbox may not have completed self-installation yet"
  fi

  log "🖥️  Creating desktop launcher..."
  _write_desktop_file "$launcher_bin_path"

  log "🔗 Creating symlink in ~/.local/bin..."
  mkdir -p "$HOME_DIR/.local/bin"
  ln -sf "$launcher_bin_path" "$SYMLINK"

  log "✅ JetBrains Toolbox installed and launcher created"
  log "📍 You can now find it in your app menu, or run: jetbrains-toolbox &"

  # Cleanup temp directory
  rm -rf "$TMP_DIR"
}

install() {
  install_toolbox
}

config() {
  require_user

  log "🔧 Verifying JetBrains Toolbox installation..."

  local launcher_bin_path
  if [[ -f "$BASE_DIR/bin/jetbrains-toolbox" ]]; then
    launcher_bin_path="$BASE_DIR/bin/jetbrains-toolbox"
  elif [[ -x "$BASE_DIR/jetbrains-toolbox" ]]; then
    launcher_bin_path="$BASE_DIR/jetbrains-toolbox"
  else
    log "❌ JetBrains Toolbox not found. Run 'install' first."
    exit 1
  fi

  # Ensure desktop launcher exists
  if [[ ! -f "$DESKTOP_FILE" ]]; then
    log "🖥️  Creating desktop launcher..."
    _write_desktop_file "$launcher_bin_path"
  else
    log "✅ Desktop launcher already exists"
  fi

  # Ensure symlink exists
  if [[ ! -L "$SYMLINK" ]]; then
    log "🔗 Creating symlink in ~/.local/bin..."
    mkdir -p "$HOME_DIR/.local/bin"
    ln -sf "$launcher_bin_path" "$SYMLINK"
    log "✅ Symlink created"
  fi

  log "✅ JetBrains Toolbox configuration complete"
}

clean() {
  require_user

  log "🧹 Removing JetBrains Toolbox..."

  if [[ -d "$BASE_DIR" ]]; then
    rm -rf "$BASE_DIR"
    log "✅ Removed JetBrains Toolbox directory"
  fi

  if [[ -f "$DESKTOP_FILE" ]]; then
    rm -f "$DESKTOP_FILE"
    update-desktop-database "$HOME_DIR/.local/share/applications" &>/dev/null || true
    log "✅ Removed desktop launcher"
  fi

  # Remove icon if it was copied
  local icon_file="$HOME_DIR/.local/share/icons/jetbrains-toolbox.svg"
  if [[ -f "$icon_file" ]]; then
    rm -f "$icon_file"
    log "✅ Removed icon"
  fi

  if [[ -L "$SYMLINK" ]] || [[ -f "$SYMLINK" ]]; then
    rm -f "$SYMLINK"
    log "✅ Removed symlink"
  fi

  log "✅ Clean complete"
}

case "$ACTION" in
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
all)
  deps
  install
  config
  ;;
*)
  echo "Usage: $0 {all|deps|install|config|clean}"
  exit 1
  ;;
esac
