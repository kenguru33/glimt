#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="vscode"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"
REPO_FILE="/etc/yum.repos.d/vscode.repo"

# ------------------------------------------------------------
# Fedora / RHEL guard
# ------------------------------------------------------------
fedora_guard() {
  [[ -r /etc/os-release ]] || {
    echo "❌ /etc/os-release missing"
    exit 1
  }

  . /etc/os-release

  [[ "$ID" == "fedora" || "$ID" == "rhel" || "$ID_LIKE" == *"fedora"* ]] || {
    echo "❌ Fedora/RHEL-based systems only."
    exit 1
  }
}

# ------------------------------------------------------------
# Dependencies + repo
# ------------------------------------------------------------
deps() {
  echo "🔧 [$MODULE_NAME] Installing dependencies and VS Code repo…"

  sudo dnf install -y curl

  if [[ ! -f "$REPO_FILE" ]]; then
    echo "➕ Adding VS Code yum repo…"

    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc

    sudo tee "$REPO_FILE" >/dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
  else
    echo "ℹ️  VS Code repo already present."
  fi
}

# ------------------------------------------------------------
# Install
# ------------------------------------------------------------
install_pkg() {
  echo "📦 [$MODULE_NAME] Installing VS Code…"
  sudo dnf install -y code
  echo "✅ VS Code installed."
  verify_binary code --version
}

# ------------------------------------------------------------
# Config (placeholder)
# ------------------------------------------------------------
config() {
  echo "⚙️  [$MODULE_NAME] No extra VS Code config yet (package defaults)."
}

# ------------------------------------------------------------
# Clean
# ------------------------------------------------------------
clean() {
  echo "🧹 [$MODULE_NAME] Removing VS Code and repo…"
  sudo dnf remove -y code || true
  sudo rm -f "$REPO_FILE"
}

# ------------------------------------------------------------
# All
# ------------------------------------------------------------
all() {
  deps
  install_pkg
  config
  echo "✅ [$MODULE_NAME] Done."
}

# ------------------------------------------------------------
# Entrypoint
# ------------------------------------------------------------
fedora_guard

case "$ACTION" in
deps) deps ;;
install) install_pkg ;;
config) config ;;
clean) clean ;;
all) all ;;
*)
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 2
  ;;
esac
