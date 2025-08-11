#!/bin/bash
set -euo pipefail
trap 'echo "❌ kubectl install failed (line $LINENO)." >&2' ERR

MODULE_NAME="kubectl"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
if [[ -z "${REAL_USER}" || "${REAL_USER}" == "root" ]]; then
  REAL_USER="$(logname 2>/dev/null || echo "$USER")"
fi

HOME_DIR="$(getent passwd "$REAL_USER" | cut -d: -f6)"
HOME_DIR="${HOME_DIR:-$HOME}"

LOCAL_BIN="$HOME_DIR/.local/bin"
PLUGIN_DIR="$HOME_DIR/.zsh/plugins/kubectl"
CONFIG_DIR="$HOME_DIR/.zsh/config"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/config/kubectl.zsh"
TARGET_FILE="$CONFIG_DIR/kubectl.zsh"
COMPLETION_FILE="$PLUGIN_DIR/kubectl.zsh"

umask 022

ensure_dirs() {
  mkdir -p "$LOCAL_BIN" "$PLUGIN_DIR" "$CONFIG_DIR"
  chown -R "$REAL_USER:$REAL_USER" "$HOME_DIR/.local" "$HOME_DIR/.zsh" 2>/dev/null || true
}

deps() {
  echo "📦 Checking dependencies..."
  if ! command -v curl >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then
      echo "➡️  Installing curl via apt-get..."
      sudo apt-get update -y
      sudo apt-get install -y curl
    else
      echo "❌ curl is not installed and I don't know how to install it on this distro."
      exit 1
    fi
  fi
}

do_install() {
  echo "⬇️ Installing kubectl → $LOCAL_BIN"
  ensure_dirs

  KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  KUBECTL_URL="https://dl.k8s.io/release/${KVER}/bin/linux/amd64/kubectl"

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
    install -o "$REAL_USER" -g "$REAL_USER" -m 0644 "$TEMPLATE_FILE" "$TARGET_FILE"
    echo "✅ $TARGET_FILE"
  else
    echo "⚠️  Template not found: $TEMPLATE_FILE (skipping)"
  fi
}

clean() {
  echo "🧹 Cleaning kubectl setup"
  rm -f "$LOCAL_BIN/kubectl"
  rm -rf "$PLUGIN_DIR"
  rm -f "$TARGET_FILE"
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
