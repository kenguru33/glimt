#!/bin/bash
# Glimt module: jq (JSON processor)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ jq module failed." >&2' ERR

MODULE_NAME="jq"
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
  # jq doesn't have special dependencies beyond what rpm-ostree provides
  log "✅ No additional dependencies required"
}

install() {
  log "🔌 Installing jq via rpm-ostree..."

  if rpm -q jq &>/dev/null; then
    log "✅ jq already installed"
  else
    log "⬇️  Installing jq..."
    local output
    output=$(sudo rpm-ostree install -y jq 2>&1) || {
      if echo "$output" | grep -q "already requested"; then
        log "✅ jq already requested in pending layer"
        log "ℹ️  A system reboot is required for the changes to take effect"
        return 0
      else
        log "❌ Failed to install jq:"
        echo "$output" >&2
        return 1
      fi
    }
    log "✅ jq installed"
    log "ℹ️  A system reboot is required for the changes to take effect"
  fi
}

config() {
  require_user

  log "🔧 Verifying jq installation..."

  # Check if jq command is available
  # Note: This may not be available until after reboot on Silverblue
  if command -v jq &>/dev/null 2>&1; then
    log "✅ jq is available: $(command -v jq)"
    log "   Version: $(jq --version 2>/dev/null || echo 'unknown')"
  else
    log "⚠️  jq command not yet available in PATH"
    log "ℹ️  A system reboot may be required for rpm-ostree changes to take effect"
  fi

  log "✅ jq configuration complete"
}

clean() {
  log "🧹 Removing jq..."

  if rpm -q jq &>/dev/null; then
    log "🔄 Uninstalling jq..."
    sudo rpm-ostree uninstall jq
    log "✅ jq uninstalled"
    log "ℹ️  A system reboot is required for the changes to take effect"
  else
    log "ℹ️  jq not installed"
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
