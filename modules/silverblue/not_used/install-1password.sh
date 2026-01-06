#!/bin/bash
# Glimt module: 1password
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ 1password module failed." >&2' ERR

MODULE_NAME="1password"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

GPG_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-1password"
REPO_FILE="/etc/yum.repos.d/1password.repo"
REPO_URL="https://downloads.1password.com/linux/rpm/stable"
GPG_KEY_URL="https://downloads.1password.com/linux/keys/1password.asc"

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
  # curl is available by default in Silverblue
  log "✅ No additional dependencies required"
}

install_repo() {
  log "🔑 Importing 1Password GPG key..."
  
  if [[ ! -f "$GPG_KEY" ]]; then
    curl -sS "$GPG_KEY_URL" | sudo tee "$GPG_KEY" >/dev/null
    log "✅ GPG key imported"
  else
    log "ℹ️  GPG key already present"
  fi

  log "➕ Adding 1Password repository..."
  
  if [[ ! -f "$REPO_FILE" ]]; then
    sudo tee "$REPO_FILE" >/dev/null <<EOF
[1password]
name=1Password Stable Channel
baseurl=$REPO_URL/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=file://$GPG_KEY
EOF
    log "✅ Repository added"
  else
    log "ℹ️  Repository already configured"
  fi
}

install_pkg() {
  log "🔌 Installing 1Password via rpm-ostree..."

  if rpm -q 1password &>/dev/null; then
    log "✅ 1Password already installed"
  else
    log "⬇️  Installing 1Password..."
    local output
    output=$(sudo rpm-ostree install -y 1password 2>&1) || {
      if echo "$output" | grep -q "already requested"; then
        log "✅ 1Password already requested in pending layer"
        log "ℹ️  A system reboot is required for the changes to take effect"
        return 0
      else
        log "❌ Failed to install 1Password:"
        echo "$output" >&2
        return 1
      fi
    }
    log "✅ 1Password installed"
    log "ℹ️  A system reboot is required for the changes to take effect"
  fi
}

install() {
  install_repo
  install_pkg
}

config() {
  require_user

  log "🔧 Verifying 1Password installation..."

  # Check if 1password command is available
  # Note: This may not be available until after reboot on Silverblue
  if command -v 1password &>/dev/null 2>&1; then
    log "✅ 1Password is available: $(command -v 1password)"
  else
    log "⚠️  1Password command not yet available in PATH"
    log "ℹ️  A system reboot may be required for rpm-ostree changes to take effect"
  fi

  log "✅ 1Password configuration complete"
}

clean() {
  log "🧹 Removing 1Password..."

  if rpm -q 1password &>/dev/null; then
    log "🔄 Uninstalling 1Password..."
    sudo rpm-ostree uninstall 1password
    log "✅ 1Password uninstalled"
    log "ℹ️  A system reboot is required for the changes to take effect"
  else
    log "ℹ️  1Password not installed"
  fi

  log "🧹 Removing repository configuration..."
  sudo rm -f "$REPO_FILE" "$GPG_KEY"
  log "✅ Repository removed"

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
