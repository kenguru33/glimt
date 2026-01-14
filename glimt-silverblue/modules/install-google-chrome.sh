#!/usr/bin/env bash
# Install Google Chrome on Fedora Silverblue / rpm-ostree systems
# Safe to re-run
# Requires reboot

set -Eeuo pipefail
trap 'echo "❌ Google Chrome install failed at line $LINENO" >&2' ERR

MODULE_NAME="google-chrome"

log() { echo "🔧 [$MODULE_NAME] $*"; }
die() {
  echo "❌ [$MODULE_NAME] $*" >&2
  exit 1
}

# --------------------------------------------------
# Guards
# --------------------------------------------------
command -v rpm-ostree >/dev/null || die "rpm-ostree not found"
[[ "$EUID" -eq 0 ]] || die "Run with sudo"

# --------------------------------------------------
# Already installed?
# --------------------------------------------------
if rpm-ostree status --json | jq -e '.deployments[0].packages[]? | contains("google-chrome")' >/dev/null 2>&1; then
  log "Google Chrome already layered"
  exit 0
fi

# --------------------------------------------------
# Install Chrome from official RPM
# --------------------------------------------------
RPM_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm"

log "Installing Google Chrome from official RPM"
rpm-ostree install "$RPM_URL"

# --------------------------------------------------
# Done
# --------------------------------------------------
log "✅ Google Chrome installed"
log "🔁 Reboot required"
