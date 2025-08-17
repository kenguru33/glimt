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
MODULE_CONF_SRC="$SCRIPT_DIR/config/azure-cli.zsh"     # modules/debian/config/azure-cli.zsh

log() { echo -e "$1"; }

require_debian() {
  if [[ -f /etc/os-release ]]; then . /etc/os-release; else
    log "❌ Cannot detect OS."; exit 1; fi
  [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]] || { log "❌ Debian-family only."; exit 1; }
}

install_dependencies() {
  log "🔧 [$MODULE_NAME] Installing dependencies…"
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg lsb-release bash-completion
}

# If MS doesn’t have Trixie yet, fall back to Bookworm.
_detect_suite() {
  local codename
  codename="$(lsb_release -cs 2>/dev/null || echo trixie)"
  case "$codename" in
    trixie) echo "bookworm" ;;
    *) echo "$codename" ;;
  esac
}

install_repo_and_package() {
  log "🏷️  [$MODULE_NAME] Adding Microsoft Azure CLI repo…"
  sudo mkdir -p /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/microsoft.gpg ]]; then
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
      | gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg >/dev/null
    sudo chmod go+r /etc/apt/keyrings/microsoft.gpg
  fi

  local suite arch srcfile
  suite="$(_detect_suite)"
  arch="$(dpkg --print-architecture)"
  srcfile="/etc/apt/sources.list.d/azure-cli.sources"
  cat <<EOF | sudo tee "$srcfile" >/dev/null
Types: deb
URIs: https://packages.microsoft.com/repos/azure-cli/
Suites: ${suite}
Components: main
Architectures: ${arch}
Signed-by: /etc/apt/keyrings/microsoft.gpg
EOF

  log "📦 [$MODULE_NAME] Installing azure-cli…"
  sudo apt-get update -y
  sudo apt-get install -y azure-cli
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
  sudo apt-get remove -y azure-cli || true
  sudo rm -f /etc/apt/sources.list.d/azure-cli.sources
  sudo rm -f /etc/apt/keyrings/microsoft.gpg
  sudo apt-get update -y || true

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

require_debian
case "$ACTION" in
  deps)    install_dependencies ;;
  install) install_repo_and_package ;;
  config)  copy_zsh_config ;;
  clean)   clean_all ;;
  all)     run_all ;;
  *) echo "Usage: $0 {all|deps|install|config|clean} [--verbose]" ; exit 2 ;;
esac
