#!/usr/bin/env bash
# Glimt module: 1password
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ 1Password module failed at line $LINENO" >&2' ERR

MODULE_NAME="1password"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

REPO_FILE="/etc/yum.repos.d/1password.repo"
GPG_KEY_URL="https://downloads.1password.com/linux/keys/1password.asc"

log() {
  printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2
}

require_sudo() {
  if [[ "$EUID" -ne 0 ]]; then
    echo "❌ This module must be run with sudo" >&2
    exit 1
  fi
}

require_silverblue() {
  [[ -f /run/ostree-booted ]] || {
    echo "❌ This module is intended for rpm-ostree based systems (Silverblue / Kinoite / Bluefin)" >&2
    exit 1
  }
}

# --------------------------------------------------
deps() {
  require_sudo
  require_silverblue

  log "🔑 Importing 1Password GPG key into ostree trust"
  rpm-ostree install "$GPG_KEY_URL" || true

  log "📦 Installing 1Password rpm-md repository"
  tee "$REPO_FILE" >/dev/null <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF
}

# --------------------------------------------------
install() {
  require_sudo
  require_silverblue

  log "📥 Installing 1Password + 1Password CLI"
  rpm-ostree install 1password 1password-cli

  log "🔁 Installation complete – reboot required"
}

# --------------------------------------------------
config() {
  log "ℹ️ No post-config required for 1Password"
  log "👉 GUI app: 1Password"
  log "👉 CLI: op"
}

# --------------------------------------------------
clean() {
  require_sudo

  log "🧹 Removing 1Password packages"
  rpm-ostree uninstall 1password 1password-cli || true

  log "🧹 Removing repo file"
  rm -f "$REPO_FILE"

  log "🔁 Reboot required to finalize removal"
}

# --------------------------------------------------
case "$ACTION" in
all)
  deps
  install
  config
  ;;
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
*)
  echo "Usage: $0 {all|deps|install|config|clean}" >&2
  exit 1
  ;;
esac
