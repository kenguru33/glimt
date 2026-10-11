#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="kubectl"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

LOCAL_BIN="$HOME_DIR/.local/bin"
PLUGIN_DIR="$HOME_DIR/.zsh/plugins/kubectl"
CONFIG_DIR="$HOME_DIR/.zsh/config"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/config/kubectl.zsh"
TARGET_FILE="$CONFIG_DIR/kubectl.zsh"
COMPLETION_FILE="$PLUGIN_DIR/kubectl.zsh"

# === OS Check (Fedora only) ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "❌ This module supports Fedora/RHEL-based systems only."
  exit 1
fi

umask 022

# Created as the user, so no chown is needed; every file written below is
# user-owned too (install -o, run_as_user, deploy_config).
ensure_dirs() {
  run_as_user mkdir -p "$LOCAL_BIN" "$PLUGIN_DIR" "$CONFIG_DIR"
}

deps() {
  echo "📦 Checking dependencies..."
  if ! command -v curl >/dev/null 2>&1; then
    echo "➡️  Installing curl via dnf..."
    sudo dnf install -y curl
  fi
}

do_install() {
  echo "⬇️ Installing kubectl → $LOCAL_BIN"
  ensure_dirs

  KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  ARCH_NORM="$(normalize_arch)"
  KUBECTL_URL="https://dl.k8s.io/release/${KVER}/bin/linux/${ARCH_NORM}/kubectl"

  local tmp
  tmp="$(mktemp)"

  echo "→ Downloading $KUBECTL_URL"
  if ! curl -fL --retry 3 --retry-delay 2 -o "$tmp" "$KUBECTL_URL"; then
    rm -f "$tmp"
    die "Download failed: $KUBECTL_URL"
  fi

  sudo install -o "$REAL_USER" -g "$REAL_USER" -m 0755 "$tmp" "$LOCAL_BIN/kubectl"
  rm -f "$tmp"

  verify_binary "$LOCAL_BIN/kubectl" version --client

  echo "📄 Generating zsh completion"
  # The redirect runs inside the user's shell, so the file is user-owned
  run_as_user sh -c '"$1" completion zsh > "$2"' _ "$LOCAL_BIN/kubectl" "$COMPLETION_FILE"

  echo "✅ kubectl installed at $LOCAL_BIN/kubectl"
  echo "✅ Completion at $COMPLETION_FILE"
}

do_config() {
  echo "📝 Installing kubectl.zsh config"
  ensure_dirs
  if [[ -f "$TEMPLATE_FILE" ]]; then
    deploy_config "$TEMPLATE_FILE" "$TARGET_FILE"
    echo "✅ $TARGET_FILE"
  else
    echo "⚠️  Template not found: $TEMPLATE_FILE (skipping)"
  fi
}

clean() {
  echo "🧹 Cleaning kubectl setup"
  sudo -u "$REAL_USER" rm -f "$LOCAL_BIN/kubectl"
  sudo -u "$REAL_USER" rm -rf "$PLUGIN_DIR"
  sudo -u "$REAL_USER" rm -f "$TARGET_FILE"
  echo "✅ Clean complete"
}

case "$ACTION" in
  all)     deps; do_install; do_config ;;
  deps)    deps ;;
  install) do_install ;;
  config)  do_config ;;
  clean)   clean ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac


