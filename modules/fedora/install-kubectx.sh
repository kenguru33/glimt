#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ kubectx module failed. Exiting." >&2' ERR

MODULE_NAME="kubectx"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

GLIMT_VERSIONS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../versions.env"
# shellcheck source=../../versions.env
source "$GLIMT_VERSIONS"

ACTION="${1:-all}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="$SCRIPT_DIR/config/kubectx.zsh"
CONFIG_DEST="$HOME_DIR/.zsh/config/kubectx.zsh"

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

# kubectx/kubens release tarballs use "x86_64" (not "amd64"), so we cannot
# use the shared normalize_arch() from lib.sh which returns "amd64".
normalize_arch_kubectx() {
  case "$(uname -m)" in
    x86_64)  echo "x86_64" ;;
    aarch64) echo "arm64" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}

# === deps ===
deps() {
  log "Checking dependencies..."
  if ! command -v curl >/dev/null 2>&1; then
    sudo dnf install -y curl
  fi
}

# === install ===
install() {
  echo "📦 Installing kubectx and kubens from GitHub releases..."

  ARCH_NORM="$(normalize_arch)"
  BIN_DIR="$HOME_DIR/.local/bin"
  sudo -u "$REAL_USER" mkdir -p "$BIN_DIR"

  # kubectx
  KUBECTX_URL="https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubectx_${KUBECTX_VERSION}_linux_${ARCH_NORM}.tar.gz"
  
  TMP_DIR="$(mktemp -d)"
  TMP_TAR="$(mktemp)"
  
  curl -fsSL "$KUBECTX_URL" -o "$TMP_TAR"
  sudo -u "$REAL_USER" tar -xzf "$TMP_TAR" -C "$TMP_DIR"
  sudo -u "$REAL_USER" mv "$TMP_DIR/kubectx" "$BIN_DIR/kubectx"
  sudo -u "$REAL_USER" chmod +x "$BIN_DIR/kubectx"
  
  rm -f "$TMP_TAR"
  
  # kubens (same release tag as kubectx)
  KUBENS_URL="https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubens_${KUBECTX_VERSION}_linux_${ARCH_NORM}.tar.gz"
  
  TMP_TAR="$(mktemp)"
  curl -fsSL "$KUBENS_URL" -o "$TMP_TAR"
  sudo -u "$REAL_USER" tar -xzf "$TMP_TAR" -C "$TMP_DIR"
  sudo -u "$REAL_USER" mv "$TMP_DIR/kubens" "$BIN_DIR/kubens"
  sudo -u "$REAL_USER" chmod +x "$BIN_DIR/kubens"
  
  rm -f "$TMP_TAR"
  rm -rf "$TMP_DIR"

  verify_binary kubectx
  verify_binary kubens
  log "✅ Installed kubectx and kubens to $BIN_DIR"
}

# === config ===
config() {
  echo "⚙️  Copying Zsh config for kubectx..."

  deploy_config "$CONFIG_SRC" "$CONFIG_DEST"

  echo "✅ Config copied to $CONFIG_DEST"
}

# === clean ===
clean() {
  echo "🧹 Removing kubectx and related config..."
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.local/bin/kubectx" "$HOME_DIR/.local/bin/kubens"
  sudo -u "$REAL_USER" rm -f "$CONFIG_DEST"
  echo "✅ Cleaned up"
}

# === entry point ===
case "$ACTION" in
  deps)    deps ;;
  install) install ;;
  config)  config ;;
  clean)   clean ;;
  all)     deps; install; config ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac


