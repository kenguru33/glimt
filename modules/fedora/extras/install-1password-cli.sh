#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] installation failed (line $LINENO)." >&2' ERR

MODULE_NAME="1password-cli"
ACTION="${1:-all}"

# === OS Detection ========================================================
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Unable to detect OS."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "❌ This script supports Fedora/RHEL-based systems only."
  exit 1
fi

# === Constants ===========================================================
FEDORA_REPO="/etc/yum.repos.d/1password-cli.repo"
DEPS=(curl ca-certificates dnf-plugins-core)

log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }

# === Dependencies ========================================================
install_deps() {
  log "Installing dependencies…"
  sudo dnf makecache -y
  sudo dnf install -y "${DEPS[@]}"
}

# === Repo ================================================================
install_repo() {
  log "Adding 1Password CLI DNF repository…"

  if [[ ! -f "$FEDORA_REPO" ]]; then
    sudo tee "$FEDORA_REPO" >/dev/null <<'EOF'
[1password-cli]
name=1Password CLI Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF
  else
    log "Repo already present."
  fi

  sudo dnf makecache -y
}

remove_repo() {
  log "Removing 1Password CLI repository…"
  sudo rm -f "$FEDORA_REPO"
  sudo dnf makecache -y
}

# === Install =============================================================
install_cli() {
  log "Installing 1Password CLI…"
  sudo dnf install -y 1password-cli
  log "1Password CLI installed."
  log "Tip: run 'op signin' to get started."
}

# === Config ==============================================================
config_cli() {
  log "Verifying 1Password CLI…"
  if command -v op >/dev/null 2>&1; then
    log "1Password CLI is installed and ready."
  else
    echo "❌ 1Password CLI not found. Run install first."
    exit 1
  fi
}

# === Clean ===============================================================
clean_cli() {
  log "Removing 1Password CLI…"
  sudo dnf remove -y 1password-cli || true
  remove_repo || true
  log "1Password CLI removed."
}

# === Dispatcher ==========================================================
case "$ACTION" in
deps)
  install_deps
  ;;
install)
  install_deps
  install_repo
  install_cli
  ;;
config)
  config_cli
  ;;
clean)
  clean_cli
  ;;
all)
  install_deps
  install_repo
  install_cli
  config_cli
  ;;
*)
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac
