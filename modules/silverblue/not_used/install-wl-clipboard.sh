#!/bin/bash
# Glimt module: wl-clipboard (Wayland clipboard utilities)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ wl-clipboard module failed." >&2' ERR

MODULE_NAME="wl-clipboard"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

log() {
  printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2
}

require_user() {
  if [[ "$EUID" -eq 0 && -z "${SUDO_USER:-}" ]]; then
    echo "❌ Do not run this module as root directly." >&2
    exit 1
  fi
}

deps() {
  log "📦 Checking dependencies..."
  # wl-clipboard doesn't have special dependencies beyond what rpm-ostree provides
  log "✅ No additional dependencies required"
}

install() {
  log "🔌 Installing wl-clipboard via rpm-ostree..."

  if rpm -q wl-clipboard &>/dev/null; then
    log "✅ wl-clipboard already installed"
  else
    log "⬇️  Installing wl-clipboard..."
    sudo rpm-ostree install -y wl-clipboard
    log "✅ wl-clipboard installed"
    log "ℹ️  A system reboot may be required for the changes to take effect"
  fi

  if ! rpm -q wl-clipboard &>/dev/null; then
    log "❌ wl-clipboard package not found after installation"
    log "ℹ️  You may need to reboot for rpm-ostree changes to take effect"
    exit 1
  fi

  log "✅ wl-clipboard is ready"
}

config() {
  require_user

  log "🔧 Verifying wl-clipboard installation..."

  if ! rpm -q wl-clipboard &>/dev/null; then
    log "❌ wl-clipboard package not found. Run 'install' first."
    exit 1
  fi

  # Check if wl-copy and wl-paste commands are available
  # Note: These may not be available until after reboot on Silverblue
  if command -v wl-copy &>/dev/null 2>&1 && command -v wl-paste &>/dev/null 2>&1; then
    log "✅ wl-clipboard commands are available:"
    log "   - wl-copy: $(command -v wl-copy)"
    log "   - wl-paste: $(command -v wl-paste)"
  else
    log "⚠️  wl-clipboard commands not yet available in PATH"
    log "ℹ️  A system reboot may be required for rpm-ostree changes to take effect"
  fi

  log "✅ wl-clipboard configuration complete"
}

clean() {
  log "🧹 Removing wl-clipboard..."

  if rpm -q wl-clipboard &>/dev/null; then
    log "🔄 Uninstalling wl-clipboard..."
    sudo rpm-ostree uninstall wl-clipboard
    log "✅ wl-clipboard uninstalled"
    log "ℹ️  A system reboot may be required for the changes to take effect"
  else
    log "ℹ️  wl-clipboard not installed"
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
