#!/usr/bin/env bash
# Glimt module: jetbrains-toolbox
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="jetbrains-toolbox"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"

BASE_DIR="$HOME_DIR/.local/share/JetBrains/Toolbox"
DESKTOP_FILE="$HOME_DIR/.local/share/applications/jetbrains-toolbox.desktop"
SYMLINK="$HOME_DIR/.local/bin/jetbrains-toolbox"
AUTOSTART_FILE="$HOME_DIR/.config/autostart/jetbrains-toolbox.desktop"

# ---- Fedora-only guard ----
fedora_guard() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    [[ "${ID:-}" == "fedora" || "${ID_LIKE:-}" == *"fedora"* || "${ID:-}" == "rhel" ]] || die "Fedora/RHEL-only module."
  else
    die "Cannot detect OS."
  fi
}

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
    run_as_user mkdir -p "$icons_dir"
    run_as_user cp -f "$icon_path" "$icons_dir/jetbrains-toolbox.svg" 2>/dev/null || true
    icon_path="$icons_dir/jetbrains-toolbox.svg"
    log "Icon copied to: $icon_path"
  elif [[ -z "$icon_path" ]]; then
    log "Icon not found, using default"
    icon_path="jetbrains-toolbox"
  fi

  run_as_user mkdir -p "$(dirname "$DESKTOP_FILE")"
  run_as_user tee "$DESKTOP_FILE" >/dev/null <<EOF
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
  run_as_user chmod +x "$DESKTOP_FILE"
  run_as_user update-desktop-database "$HOME_DIR/.local/share/applications" &>/dev/null || true
  log "Desktop launcher created"
}

deps() {
  log "Installing dependencies..."
  # curl + jq resolve and fetch the latest release, tar unpacks it
  dnf_ensure curl jq tar
}

install_toolbox() {
  log "Installing JetBrains Toolbox..."

  if [[ -d "$BASE_DIR" && -x "$BASE_DIR/jetbrains-toolbox" ]] || [[ -f "$BASE_DIR/bin/jetbrains-toolbox" ]]; then
    log "JetBrains Toolbox already installed"
    return 0
  fi

  local tmp_dir
  tmp_dir="$(run_as_user mktemp -d "${TMPDIR:-/tmp}/glimt-jetbrains-toolbox.XXXXXX")"

  log "Fetching latest JetBrains Toolbox download URL..."
  local url
  url=$(curl -fsSL "https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release" \
    | jq -r '.TBA[0].downloads.linux.link')

  if [[ -z "$url" || "$url" == "null" ]]; then
    log "Failed to fetch download URL"
    exit 1
  fi

  local filename="$tmp_dir/${url##*/}"
  log "⬇️  Downloading: ${url##*/}"
  run_as_user curl -fL "$url" -o "$filename"

  log "Extracting to: $BASE_DIR"
  run_as_user rm -rf "$BASE_DIR"
  run_as_user mkdir -p "$BASE_DIR"
  run_as_user tar -xzf "$filename" --strip-components=1 -C "$BASE_DIR"

  log "Launching JetBrains Toolbox for first-time setup..."
  run_as_user nohup "$BASE_DIR/jetbrains-toolbox" >/dev/null 2>&1 &

  sleep 5

  # Detect relocated binary (after first launch)
  local launcher_bin_path
  if [[ -f "$BASE_DIR/bin/jetbrains-toolbox" ]]; then
    launcher_bin_path="$BASE_DIR/bin/jetbrains-toolbox"
  else
    launcher_bin_path="$BASE_DIR/jetbrains-toolbox"
    log "Toolbox may not have completed self-installation yet"
  fi

  log "Creating desktop launcher..."
  _write_desktop_file "$launcher_bin_path"

  log "Creating symlink in ~/.local/bin..."
  run_as_user mkdir -p "$HOME_DIR/.local/bin"
  run_as_user ln -sf "$launcher_bin_path" "$SYMLINK"

  log "JetBrains Toolbox installed and launcher created"
  log "You can now find it in your app menu, or run: jetbrains-toolbox &"

  # Cleanup temp directory
  run_as_user rm -rf "$tmp_dir"
}

install() {
  install_toolbox
}

config() {
  log "Verifying JetBrains Toolbox installation..."

  local launcher_bin_path
  if [[ -f "$BASE_DIR/bin/jetbrains-toolbox" ]]; then
    launcher_bin_path="$BASE_DIR/bin/jetbrains-toolbox"
  elif [[ -x "$BASE_DIR/jetbrains-toolbox" ]]; then
    launcher_bin_path="$BASE_DIR/jetbrains-toolbox"
  else
    log "JetBrains Toolbox not found. Run 'install' first."
    exit 1
  fi

  # Ensure desktop launcher exists
  if [[ ! -f "$DESKTOP_FILE" ]]; then
    log "Creating desktop launcher..."
    _write_desktop_file "$launcher_bin_path"
  else
    log "Desktop launcher already exists"
  fi

  # Ensure symlink exists
  if [[ ! -L "$SYMLINK" ]]; then
    log "Creating symlink in ~/.local/bin..."
    run_as_user mkdir -p "$HOME_DIR/.local/bin"
    run_as_user ln -sf "$launcher_bin_path" "$SYMLINK"
    log "Symlink created"
  fi

  PATH="$(dirname "$SYMLINK"):$PATH" verify_binary jetbrains-toolbox

  log "JetBrains Toolbox configuration complete"
}

clean() {
  log "Removing JetBrains Toolbox..."

  # Stop a running Toolbox first. Match on its install path, not just the
  # name — a bare "jetbrains-toolbox" pattern would also match this script.
  pkill -u "$REAL_USER" -f "$BASE_DIR/(bin/)?jetbrains-toolbox( |\$)" 2>/dev/null || true

  if [[ -d "$BASE_DIR" ]]; then
    run_as_user rm -rf "$BASE_DIR"
    log "Removed JetBrains Toolbox directory"
  fi

  if [[ -f "$DESKTOP_FILE" ]]; then
    run_as_user rm -f "$DESKTOP_FILE"
    run_as_user update-desktop-database "$HOME_DIR/.local/share/applications" &>/dev/null || true
    log "Removed desktop launcher"
  fi

  # Remove icon if it was copied
  local icon_file="$HOME_DIR/.local/share/icons/jetbrains-toolbox.svg"
  if [[ -f "$icon_file" ]]; then
    run_as_user rm -f "$icon_file"
    log "Removed icon"
  fi

  if [[ -L "$SYMLINK" ]] || [[ -f "$SYMLINK" ]]; then
    run_as_user rm -f "$SYMLINK"
    log "Removed symlink"
  fi

  # Toolbox registers itself for autostart on first launch
  if [[ -f "$AUTOSTART_FILE" ]]; then
    run_as_user rm -f "$AUTOSTART_FILE"
    log "Removed autostart entry"
  fi

  log "Clean complete"
}

fedora_guard

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
