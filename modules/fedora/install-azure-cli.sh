#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="azure-cli"

# Args: {all|deps|install|config|clean} [--verbose]
VERBOSE=false
ACTION="${1:-all}"
for arg in "$@"; do
  case "$arg" in
  all | deps | install | config | clean) ACTION="$arg" ;;
  -v | --verbose) VERBOSE=true ;;
  esac
done
$VERBOSE && set -x || true

# === OS detection ========================================================
[[ -r /etc/os-release ]] || {
  echo "❌ Cannot detect OS."
  exit 1
}
. /etc/os-release
[[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || {
  echo "❌ Fedora/RHEL-family only."
  exit 1
}

# === Real user ===========================================================
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# === Paths ===============================================================
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MODULE_CONF_SRC="$SCRIPT_DIR/config/azure-cli.zsh"

# === Config ==============================================================
DEPS=(ca-certificates curl dnf-plugins-core bash-completion)
FEDORA_VER="$(rpm -E %fedora)"
MS_REPO_PKG="https://packages.microsoft.com/config/fedora/${FEDORA_VER}/packages-microsoft-prod.rpm"

log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }

# === Deps ================================================================
install_dependencies() {
  log "Installing dependencies…"
  sudo dnf makecache -y
  sudo dnf install -y "${DEPS[@]}"
}

# === Repo + Install ======================================================
install_repo_and_package() {
  if ! rpm -q packages-microsoft-prod >/dev/null 2>&1; then
    log "Installing Microsoft repo (Fedora ${FEDORA_VER})…"
    sudo dnf install -y "$MS_REPO_PKG"
    sudo dnf makecache -y
  else
    log "Microsoft repo already present."
  fi

  log "Installing azure-cli…"
  sudo dnf install -y azure-cli
  log "azure-cli installed."
}

# === Config ==============================================================
copy_zsh_config() {
  log "Installing Zsh config…"
  [[ -f "$MODULE_CONF_SRC" ]] || {
    echo "❌ Missing module config: $MODULE_CONF_SRC"
    exit 1
  }
  sudo -u "$REAL_USER" mkdir -p "$REAL_HOME/.zsh/config"
  install -m 0644 -o "$REAL_USER" -g "$REAL_USER" \
    "$MODULE_CONF_SRC" "$REAL_HOME/.zsh/config/azure-cli.zsh"
  log "Wrote: $REAL_HOME/.zsh/config/azure-cli.zsh"
}

# === Clean ===============================================================
clean_all() {
  log "Removing azure-cli…"
  sudo dnf remove -y azure-cli || true

  log "Microsoft repo kept (used by other tooling)."
  # If you REALLY want to remove it:
  # sudo dnf remove -y packages-microsoft-prod || true

  log "Removing Zsh config…"
  rm -f "$REAL_HOME/.zsh/config/azure-cli.zsh" 2>/dev/null || true
  log "Clean completed."
}

# === Dispatcher ==========================================================
case "$ACTION" in
deps) install_dependencies ;;
install) install_repo_and_package ;;
config) copy_zsh_config ;;
clean) clean_all ;;
all)
  install_dependencies
  install_repo_and_package
  copy_zsh_config
  log "Reload Zsh or open a new terminal to activate completion."
  ;;
*)
  echo "Usage: $0 {all|deps|install|config|clean} [--verbose]"
  exit 2
  ;;
esac
