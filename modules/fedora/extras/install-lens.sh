#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="lens"

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

# Lens repository configuration
LENS_REPO="/etc/yum.repos.d/lens.repo"

install_deps() {
  echo "Installing dependencies..."
  sudo dnf install -y dnf-plugins-core curl
}

install_lens() {
  echo "Installing Lens Desktop..."

  if command -v lens-desktop &>/dev/null || command -v lens &>/dev/null; then
    echo "Lens is already installed."
    return
  fi

  echo "Adding Lens repository..."
  if [[ -f "$LENS_REPO" ]]; then
    echo "ℹ️  Lens repository already exists, removing old one..."
    sudo rm -f "$LENS_REPO"
  fi
  sudo dnf config-manager addrepo --from-repofile=https://downloads.k8slens.dev/rpm/lens.repo

  echo "⬇️ Installing Lens..."
  sudo dnf install -y lens

  echo "Lens Desktop installed."
}

config_lens() {
  echo "Configuring Lens (no Fedora-specific tweaks yet)..."
}

clean_lens() {
  echo "Removing Lens Desktop..."
  # Remove only what is actually installed: dnf errors on unknown packages,
  # which would make `|| true` hide a real removal failure too.
  local p
  for p in lens-desktop lens; do
    if rpm -q "$p" &>/dev/null; then
      sudo dnf remove -y "$p" || true
    fi
  done
  if [[ -f "$LENS_REPO" ]]; then
    sudo rm -f "$LENS_REPO"
  fi
  echo "Lens Desktop removed."
}

fedora_guard

case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_deps
    install_lens
    ;;
  config)
    config_lens
    ;;
  clean)
    clean_lens
    ;;
  all)
    install_deps
    install_lens
    config_lens
    ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac


