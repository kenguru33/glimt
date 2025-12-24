#!/bin/bash
set -e
trap 'echo "❌ kubectx module failed. Exiting." >&2' ERR

MODULE_NAME="kubectx"
ACTION="${1:-all}"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

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

# === Normalize Architecture ===
normalize_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) echo "x86_64" ;;
    aarch64) echo "arm64" ;;
    *)
      echo "❌ Unsupported architecture: $arch"
      exit 1
      ;;
  esac
}

# === install ===
install() {
  echo "📦 Installing kubectx and kubens from GitHub releases..."

  ARCH_NORM="$(normalize_arch)"
  BIN_DIR="$HOME_DIR/.local/bin"
  sudo -u "$REAL_USER" mkdir -p "$BIN_DIR"

  # kubectx
  KUBECTX_VERSION="v0.9.5"
  KUBECTX_URL="https://github.com/ahmetb/kubectx/releases/download/${KUBECTX_VERSION}/kubectx_${KUBECTX_VERSION}_linux_${ARCH_NORM}.tar.gz"
  
  TMP_DIR="$(mktemp -d)"
  TMP_TAR="$(mktemp)"
  
  curl -fsSL "$KUBECTX_URL" -o "$TMP_TAR"
  sudo -u "$REAL_USER" tar -xzf "$TMP_TAR" -C "$TMP_DIR"
  sudo -u "$REAL_USER" mv "$TMP_DIR/kubectx" "$BIN_DIR/kubectx"
  sudo -u "$REAL_USER" chmod +x "$BIN_DIR/kubectx"
  
  rm -f "$TMP_TAR"
  
  # kubens
  KUBENS_VERSION="v0.9.5"
  KUBENS_URL="https://github.com/ahmetb/kubectx/releases/download/${KUBENS_VERSION}/kubens_${KUBENS_VERSION}_linux_${ARCH_NORM}.tar.gz"
  
  TMP_TAR="$(mktemp)"
  curl -fsSL "$KUBENS_URL" -o "$TMP_TAR"
  sudo -u "$REAL_USER" tar -xzf "$TMP_TAR" -C "$TMP_DIR"
  sudo -u "$REAL_USER" mv "$TMP_DIR/kubens" "$BIN_DIR/kubens"
  sudo -u "$REAL_USER" chmod +x "$BIN_DIR/kubens"
  
  rm -f "$TMP_TAR"
  rm -rf "$TMP_DIR"

  echo "✅ Installed kubectx and kubens to $BIN_DIR"
}

# === config ===
config() {
  echo "⚙️  Copying Zsh config for kubectx..."

  if [[ ! -f "$CONFIG_SRC" ]]; then
    echo "❌ Config file not found: $CONFIG_SRC"
    exit 1
  fi

  sudo -u "$REAL_USER" mkdir -p "$(dirname "$CONFIG_DEST")"
  sudo -u "$REAL_USER" cp "$CONFIG_SRC" "$CONFIG_DEST"
  chown "$REAL_USER:$REAL_USER" "$CONFIG_DEST"

  echo "✅ Config copied to $CONFIG_DEST"
}

# === clean ===
clean() {
  echo "🧹 Removing kubectx and related config..."
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.local/bin/kubectx" "$HOME_DIR/.local/bin/kubens"
  sudo -u "$REAL_USER" rm -f "$CONFIG_DEST"
  echo "✅ Cleaned up"
}

# === all ===
all() {
  install
  config
}

# === entry point ===
case "$ACTION" in
  install) install ;;
  config) config ;;
  clean) clean ;;
  all) all ;;
  *)
    echo "Usage: $0 [all|install|config|clean]"
    exit 1
    ;;
esac


