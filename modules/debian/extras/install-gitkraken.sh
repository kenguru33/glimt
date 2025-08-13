#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="gitkraken"
ACTION="${1:-all}"

# ===== Debian-only guard =====
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]] || {
    echo "❌ Debian only."
    exit 1
  }
else
  echo "❌ Cannot detect OS."
  exit 1
fi

# ===== Config =====
ARCH="$(dpkg --print-architecture)"
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/glimt/$MODULE_NAME}"
DEB_URL="https://release.gitkraken.com/linux/gitkraken-amd64.deb"
DEB_FILE="$CACHE_DIR/gitkraken-amd64.deb"
PKG_NAME="gitkraken"

# ===== Deps =====
DEPS=(wget ca-certificates)

do_deps() {
  echo "→ Installing dependencies..."
  sudo apt update
  sudo apt install -y "${DEPS[@]}"
}

# ===== Helpers =====
installed_version() {
  dpkg-query -W -f='${Version}' "$PKG_NAME" 2>/dev/null || true
}

remote_version() {
  dpkg-deb -f "$DEB_FILE" Version
}

download_deb() {
  mkdir -p "$CACHE_DIR"
  echo "→ Downloading GitKraken .deb..."
  local tmp="$DEB_FILE.part"
  rm -f "$tmp"
  wget -qO "$tmp" "$DEB_URL"
  mv "$tmp" "$DEB_FILE"
}

needs_install_or_upgrade() {
  local inst ver
  inst="$(installed_version)"
  ver="$(remote_version)"

  [[ -z "$inst" ]] && return 0
  dpkg --compare-versions "$ver" gt "$inst"
}

# ===== Install =====
install_pkg_file() {
  [[ "$ARCH" == "amd64" ]] || {
    echo "❌ GitKraken provides amd64 only. Detected: $ARCH"
    exit 1
  }

  download_deb
  echo "→ Checking versions..."
  local remote_ver
  remote_ver="$(remote_version)"
  if needs_install_or_upgrade; then
    echo "→ Installing $PKG_NAME ($remote_ver)..."
    sudo apt install -y "$DEB_FILE"
  else
    echo "✓ $PKG_NAME is up to date ($remote_ver). Skipping install."
  fi
}

do_install() {
  do_deps
  install_pkg_file
  do_verify
}

# ===== Config (placeholder) =====
do_config() {
  : # No extra config required currently.
}

# ===== Clean =====
do_clean() {
  echo "→ Removing $PKG_NAME and cache..."
  sudo apt purge -y "$PKG_NAME" || true
  sudo apt autoremove -y || true
  rm -rf "$CACHE_DIR"
}

# ===== Verify =====
do_verify() {
  if command -v gitkraken >/dev/null 2>&1; then
    echo "✓ Installed: $(apt-cache policy gitkraken | awk '/Installed:/ {print $2}')"
  else
    echo "❌ gitkraken not on PATH."
    exit 1
  fi
}

# ===== Entry =====
case "$ACTION" in
deps) do_deps ;;
install) do_install ;;
config) do_config ;;
clean) do_clean ;;
all)
  do_deps
  install_pkg_file
  do_config
  do_verify
  ;;
*)
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac
