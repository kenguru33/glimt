#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error on line $LINENO" >&2' ERR

MODULE_NAME="azure-cli"

# Args: {all|deps|install|config|clean} [--verbose]
VERBOSE=false
ACTION="${1:-all}"
for arg in "$@"; do
  case "$arg" in
    all|deps|install|config|clean) ACTION="$arg" ;;
    -v|--verbose) VERBOSE=true ;;
  esac
done
$VERBOSE && set -x || true

# Real user (not root when running via sudo)
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# Repo-local paths (relative to this script)
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MODULE_CONF_SRC="$SCRIPT_DIR/config/azure-cli.zsh"     # modules/fedora/config/azure-cli.zsh

log() { echo -e "$1"; }

require_fedora() {
  if [[ -f /etc/os-release ]]; then . /etc/os-release; else
    log "❌ Cannot detect OS."; exit 1; fi
  [[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || { log "❌ Fedora/RHEL-family only."; exit 1; }
}

install_dependencies() {
  log "🔧 [$MODULE_NAME] Installing dependencies…"
  sudo dnf makecache -y
  sudo dnf install -y ca-certificates curl gpg bash-completion
}

_detect_fedora_version() {
  local version_id
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    version_id="${VERSION_ID:-}"
  fi
  
  # For Fedora, use RHEL 9.0 repo (works for most recent Fedora versions)
  # For older versions, could map to RHEL 8.0 or 7.0, but 9.0 is generally safe
  echo "9.0"
}

install_repo_and_package() {
  log "🏷️  [$MODULE_NAME] Adding Microsoft Azure CLI repo…"
  
  # Import Microsoft GPG key (idempotent)
  log "🔑 Importing Microsoft GPG key…"
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  
  # Install Microsoft repository configuration
  local repo_version
  repo_version="$(_detect_fedora_version)"
  if ! rpm -q packages-microsoft-prod >/dev/null 2>&1; then
    sudo dnf install -y "https://packages.microsoft.com/config/rhel/${repo_version}/packages-microsoft-prod.rpm"
  fi

  log "📦 [$MODULE_NAME] Installing azure-cli…"
  sudo dnf makecache -y
  sudo dnf install -y azure-cli
  log "✅ [$MODULE_NAME] azure-cli installed."
}

copy_zsh_config() {
  log "📁 [$MODULE_NAME] Installing Zsh config to ~/.zsh/config/…"
  if [[ ! -f "$MODULE_CONF_SRC" ]]; then
    log "❌ [$MODULE_NAME] Missing module config: $MODULE_CONF_SRC"
    exit 1
  fi
  sudo -u "$REAL_USER" mkdir -p "$REAL_HOME/.zsh/config"
  # Use install to set deterministic perms
  install -m 0644 -o "$REAL_USER" -g "$REAL_USER" "$MODULE_CONF_SRC" "$REAL_HOME/.zsh/config/azure-cli.zsh"
  log "✅ [$MODULE_NAME] Wrote: $REAL_HOME/.zsh/config/azure-cli.zsh"
}

clean_all() {
  log "🧹 [$MODULE_NAME] Removing azure-cli and repo/key…"
  sudo dnf remove -y azure-cli || true
  sudo dnf remove -y packages-microsoft-prod || true
  # Note: GPG key is left in place as it may be used by other Microsoft packages

  log "🧽 [$MODULE_NAME] Removing Zsh config…"
  rm -f "$REAL_HOME/.zsh/config/azure-cli.zsh" 2>/dev/null || true
  log "✅ [$MODULE_NAME] Clean completed."
}

run_all() {
  install_dependencies
  install_repo_and_package
  copy_zsh_config
  log "ℹ️  [$MODULE_NAME] Reload Zsh or open a new terminal to activate completion."
}

require_fedora
case "$ACTION" in
  deps)    install_dependencies ;;
  install) install_repo_and_package ;;
  config)  copy_zsh_config ;;
  clean)   clean_all ;;
  all)     run_all ;;
  *) echo "Usage: $0 {all|deps|install|config|clean} [--verbose]" ; exit 2 ;;
esac

