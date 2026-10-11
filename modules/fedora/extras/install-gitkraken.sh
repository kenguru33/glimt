#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="gitkraken"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"

# ---- Fedora-only guard ----
fedora_guard() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    [[ "${ID:-}" == "fedora" || "${ID_LIKE:-}" == *"fedora"* || "${ID:-}" == "rhel" ]] || die "Fedora/RHEL-only module."
  else
    die "Cannot detect OS."
  fi
}

# ===== Config =====
CACHE_DIR="${CACHE_DIR:-$HOME_DIR/.cache/glimt/$MODULE_NAME}"
RPM_URL="https://release.gitkraken.com/linux/gitkraken-amd64.rpm"
RPM_FILE="$CACHE_DIR/gitkraken-amd64.rpm"
PKG_NAME="gitkraken"

# ===== Deps =====
DEPS=(curl)

do_deps() {
  echo "→ [$MODULE_NAME] Installing dependencies..."
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
  run_as_user rm -f "$tmp"
  if ! sudo -u "$REAL_USER" curl -fL "$RPM_URL" -o "$tmp"; then
    echo "❌ Failed to download GitKraken RPM"
    exit 1
  fi
  
  # Verify it's actually an RPM file
  if ! file "$tmp" | grep -qE "(RPM|rpm)"; then
    echo "❌ Downloaded file is not a valid RPM file"
    echo "   File type: $(file "$tmp")"
    run_as_user rm -f "$tmp"
    exit 1
  fi
  
  run_as_user mv -f "$tmp" "$RPM_FILE"
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
# GitKraken only publishes an x86_64 RPM
supported_arch() {
  local arch
  arch="$(normalize_arch 2>/dev/null || true)"
  [[ "$arch" == "amd64" ]]
}

install_pkg_file() {
  if ! supported_arch; then
    # warn + exit 0 so setup-extras / glimt update carry on with other modules
    warn "GitKraken provides x86_64 builds only (detected: $(uname -m)) — skipping."
    exit 0
  fi

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
  verify_binary gitkraken
}

# ===== Entry =====
fedora_guard

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


