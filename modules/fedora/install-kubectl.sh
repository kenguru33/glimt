#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ kubectl install failed (line $LINENO)." >&2' ERR

MODULE_NAME="kubectl"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"

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

# === Normalize Architecture ===
umask 022

ensure_dirs() {
  sudo -u "$REAL_USER" mkdir -p "$LOCAL_BIN" "$PLUGIN_DIR" "$CONFIG_DIR"
  chown -R "$REAL_USER:$REAL_USER" "$HOME_DIR/.local" "$HOME_DIR/.zsh" 2>/dev/null || true
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

  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' RETURN

  echo "→ Downloading $KUBECTL_URL"
  curl -fL --retry 3 --retry-delay 2 -o "$tmp" "$KUBECTL_URL"

  sudo install -o "$REAL_USER" -g "$REAL_USER" -m 0755 "$tmp" "$LOCAL_BIN/kubectl"

  echo "→ Verifying kubectl binary"
  sudo -u "$REAL_USER" "$LOCAL_BIN/kubectl" version --client --output=yaml >/dev/null 2>&1 || {
    echo "❌ kubectl failed to execute after install"
    exit 1
  }

  echo "📄 Generating zsh completion"
  tmpc="$(mktemp)"
  sudo -u "$REAL_USER" "$LOCAL_BIN/kubectl" completion zsh > "$tmpc"
  install -o "$REAL_USER" -g "$REAL_USER" -m 0644 "$tmpc" "$COMPLETION_FILE"
  rm -f "$tmpc"

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


