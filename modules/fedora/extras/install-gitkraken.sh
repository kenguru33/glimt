#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="gitkraken"
ACTION="${1:-all}"

# ===== Fedora-only guard =====
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  [[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || {
    echo "❌ Fedora/RHEL only."
    exit 1
  }
else
  echo "❌ Cannot detect OS."
  exit 1
fi

# ===== Config =====
ARCH="$(uname -m)"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
CACHE_DIR="${CACHE_DIR:-$HOME_DIR/.cache/glimt/$MODULE_NAME}"
RPM_URL="https://release.gitkraken.com/linux/gitkraken-amd64.rpm"
RPM_FILE="$CACHE_DIR/gitkraken-amd64.rpm"
PKG_NAME="gitkraken"

# ===== Deps =====
DEPS=(curl)

do_deps() {
  echo "→ [$MODULE_NAME] Installing dependencies..."
  sudo dnf makecache -y
  sudo dnf install -y "${DEPS[@]}"
}

# ===== Helpers =====
installed_version() {
  rpm -q --queryformat '%{VERSION}' "$PKG_NAME" 2>/dev/null || true
}

remote_version() {
  rpm -qp --queryformat '%{VERSION}' "$RPM_FILE" 2>/dev/null || echo ""
}

download_rpm() {
  sudo -u "$REAL_USER" mkdir -p "$CACHE_DIR"
  echo "→ Downloading GitKraken .rpm..."
  local tmp="$RPM_FILE.part"
  rm -f "$tmp"
  if ! sudo -u "$REAL_USER" curl -fL "$RPM_URL" -o "$tmp"; then
    echo "❌ Failed to download GitKraken RPM"
    exit 1
  fi
  
  # Verify it's actually an RPM file
  if ! file "$tmp" | grep -qE "(RPM|rpm)"; then
    echo "❌ Downloaded file is not a valid RPM file"
    echo "   File type: $(file "$tmp")"
    rm -f "$tmp"
    exit 1
  fi
  
  mv "$tmp" "$RPM_FILE"
  chown "$REAL_USER:$REAL_USER" "$RPM_FILE"
}

needs_install_or_upgrade() {
  local inst ver
  inst="$(installed_version)"
  ver="$(remote_version)"
  
  [[ -z "$inst" ]] && return 0
  [[ -z "$ver" ]] && return 0
  
  # Simple version comparison: if remote version is different, upgrade
  [[ "$ver" != "$inst" ]]
}

# ===== Install =====
install_pkg_file() {
  [[ "$ARCH" == "x86_64" ]] || {
    echo "❌ GitKraken provides x86_64 only. Detected: $ARCH"
    exit 1
  }

  download_rpm
  echo "→ Checking versions..."
  local remote_ver inst_ver
  remote_ver="$(remote_version)"
  inst_ver="$(installed_version)"
  
  if needs_install_or_upgrade; then
    echo "→ Installing $PKG_NAME ($remote_ver)..."
    sudo dnf install -y "$RPM_FILE"
  else
    echo "✓ $PKG_NAME is up to date ($inst_ver). Skipping install."
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
  echo "→ [$MODULE_NAME] Removing $PKG_NAME and cache..."
  sudo dnf remove -y "$PKG_NAME" || true
  sudo -u "$REAL_USER" rm -rf "$CACHE_DIR" 2>/dev/null || true
  echo "✅ Clean complete."
}

# ===== Verify =====
do_verify() {
  if command -v gitkraken >/dev/null 2>&1; then
    local version
    version="$(installed_version)"
    echo "✓ Installed: $version"
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

