#!/usr/bin/env bash
# Glimt module: rpmfusion
# Actions: all | install | clean | status

set -Eeuo pipefail
trap 'echo "❌ [rpmfusion] failed at line $LINENO" >&2' ERR

MODULE_NAME="rpmfusion"
ACTION="${1:-all}"

log() { echo "🔧 [$MODULE_NAME] $*"; }
die() { echo "❌ [$MODULE_NAME] $*" >&2; exit 1; }

# --------------------------------------------------
# Guards
# --------------------------------------------------
[[ -f /run/ostree-booted ]] || die "rpm-ostree system required"
command -v rpm-ostree >/dev/null || die "rpm-ostree not found"

FEDORA_VERSION="$(rpm -E %fedora)"

RPMFUSION_FREE_URL="https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm"
RPMFUSION_NONFREE_URL="https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"

# --------------------------------------------------
# State detection (no jq needed)
# --------------------------------------------------
has_pkg() {
  rpm-ostree status | grep -qE "(^|\s)$1-[0-9]"
}

has_rpmfusion_free() {
  has_pkg rpmfusion-free-release
}

has_rpmfusion_nonfree() {
  has_pkg rpmfusion-nonfree-release
}

has_rpmfusion() {
  has_rpmfusion_free && has_rpmfusion_nonfree
}

# --------------------------------------------------
status() {
  if has_rpmfusion; then
    log "✔ RPM Fusion (free + nonfree) installed"
  else
    log "✘ RPM Fusion missing or incomplete"
  fi
}

# --------------------------------------------------
install() {
  if has_rpmfusion; then
    log "RPM Fusion already installed — nothing to do"
    return
  fi

  log "Bootstrapping RPM Fusion (URL install)"
  sudo rpm-ostree install \
    "$RPMFUSION_FREE_URL" \
    "$RPMFUSION_NONFREE_URL"

  log "Replacing URL RPMs with repo-tracked packages"
  sudo rpm-ostree update \
    --uninstall rpmfusion-free-release \
    --uninstall rpmfusion-nonfree-release \
    --install rpmfusion-free-release \
    --install rpmfusion-nonfree-release

  log "✅ RPM Fusion installed"
  log "⚠️  Reboot required"
}

# --------------------------------------------------
clean() {
  if ! has_rpmfusion; then
    log "RPM Fusion already removed"
    return
  fi

  log "Removing RPM Fusion"
  sudo rpm-ostree uninstall \
    rpmfusion-free-release \
    rpmfusion-nonfree-release

  log "⚠️  Reboot required"
}

# --------------------------------------------------
case "$ACTION" in
  all|install)
    install
    ;;
  clean)
    clean
    ;;
  status)
    status
    ;;
  *)
    die "Unknown action: $ACTION"
    ;;
esac
