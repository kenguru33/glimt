#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="tableplus"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"

# ---- Fedora-only guard ----
fedora_guard() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    [[ "${ID:-}" == "fedora" || "${ID_LIKE:-}" == *"fedora"* || "${ID:-}" == "rhel" ]] || die "Fedora/RHEL-only module."
  else
    die "Cannot detect OS."
  fi
}

TABLEPLUS_REPO="/etc/yum.repos.d/tableplus.repo"
TABLEPLUS_GPG_KEY_URL="https://yum.tableplus.com/apt.tableplus.com.gpg.key"
# TablePlus only publishes an x86_64 RPM repo
TABLEPLUS_REPOFILE_URL="https://yum.tableplus.com/rpm/x86_64/tableplus.repo"

install_deps() {
  echo "📦 Installing dependencies..."
  sudo dnf install -y dnf-plugins-core
}

install_tableplus() {
  echo "🧰 Installing TablePlus..."

  local arch
  arch="$(normalize_arch 2>/dev/null || true)"
  if [[ "$arch" != "amd64" ]]; then
    # warn + exit 0 so setup-extras / glimt update carry on with other modules
    warn "TablePlus provides x86_64 builds only (detected: $(uname -m)) — skipping."
    exit 0
  fi

  if command -v tableplus &>/dev/null || rpm -q tableplus &>/dev/null; then
    echo "✅ TablePlus is already installed."
    return
  fi

  echo "🔑 Importing GPG key..."
  sudo rpm -v --import "$TABLEPLUS_GPG_KEY_URL"

  echo "📁 Adding TablePlus repository..."
  if [[ -f "$TABLEPLUS_REPO" ]]; then
    echo "ℹ️  TablePlus repo already exists, removing old one..."
    sudo rm -f "$TABLEPLUS_REPO"
  fi

  # Using the same pattern as other Fedora extras (dnf config-manager addrepo --from-repofile=...)
  sudo dnf config-manager addrepo --from-repofile="$TABLEPLUS_REPOFILE_URL"

  echo "⬇️  Installing TablePlus..."
  sudo dnf install -y tableplus

  echo "✅ TablePlus installed."
}

config_tableplus() {
  echo "⚙️  Configuring TablePlus (no Fedora-specific tweaks yet)..."
}

clean_tableplus() {
  echo "🧹 Removing TablePlus..."
  sudo dnf remove -y tableplus || true
  if [[ -f "$TABLEPLUS_REPO" ]]; then
    sudo rm -f "$TABLEPLUS_REPO"
  fi
  echo "✅ TablePlus removed."
}

fedora_guard

case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_deps
    install_tableplus
    ;;
  config)
    config_tableplus
    ;;
  clean)
    clean_tableplus
    ;;
  all)
    install_deps
    install_tableplus
    config_tableplus
    ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac


