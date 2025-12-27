#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] installation failed (line $LINENO)." >&2' ERR

MODULE_NAME="1password"
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
FEDORA_REPO="/etc/yum.repos.d/1password.repo"
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
  log "Adding 1Password DNF repository…"

  if [[ ! -f "$FEDORA_REPO" ]]; then
    sudo tee "$FEDORA_REPO" >/dev/null <<'EOF'
[1password]
name=1Password Stable Channel
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
  log "Removing 1Password repository…"
  sudo rm -f "$FEDORA_REPO"
  sudo dnf makecache -y
}

# === Install =============================================================
install_1password() {
  log "Installing 1Password…"
  sudo dnf install -y 1password
  log "1Password installed."
}

# === Config ==============================================================
config_1password() {
  log "Verifying installation…"
  if command -v 1password >/dev/null 2>&1 || rpm -q 1password >/dev/null 2>&1; then
    log "1Password is installed and ready."
  else
    echo "❌ 1Password not found. Run install first."
    exit 1
  fi
}

# === Clean ===============================================================
clean_1password() {
  log "Removing 1Password…"
  sudo dnf remove -y 1password || true
  remove_repo || true
  log "1Password removed."
}

# === Dispatcher ==========================================================
case "$ACTION" in
deps)
  install_deps
  ;;
install)
  install_deps
  install_repo
  install_1password
  ;;
config)
  config_1password
  ;;
clean)
  clean_1password
  ;;
all)
  install_deps
  install_repo
  install_1password
  config_1password
  ;;
*)
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac
