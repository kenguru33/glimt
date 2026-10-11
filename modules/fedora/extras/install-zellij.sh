#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

# === Metadata ===
MODULE_NAME="zellij"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

SCRIPT_NAME="install-zellij.sh"
ACTION="${1:-all}"
ZELLIJ_CONFIG_DIR="$HOME_DIR/.config/zellij"
ZELLIJ_CONFIG_FILE="$ZELLIJ_CONFIG_DIR/config.kdl"
ZELLIJ_BIN="$HOME_DIR/.local/bin/zellij"
ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
CONFIG_TEMPLATE_DIR="$(dirname "${BASH_SOURCE[0]}")/../config"
LOCAL_CONFIG_TEMPLATE="$CONFIG_TEMPLATE_DIR/zellij.zsh"
KDL_TEMPLATE="$CONFIG_TEMPLATE_DIR/zellij.kdl"
ZSH_TARGET_CONFIG="$ZSH_CONFIG_DIR/zellij.zsh"

# ---- Fedora-only guard ----
fedora_guard() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    [[ "${ID:-}" == "fedora" || "${ID_LIKE:-}" == *"fedora"* || "${ID:-}" == "rhel" ]] || die "Fedora/RHEL-only module."
  else
    die "Cannot detect OS."
  fi
}

# === Dependencies ===
DEPS=(curl tar wl-clipboard)

install_deps() {
  echo "Installing dependencies..."
  sudo dnf install -y "${DEPS[@]}"
}

install() {
  echo "Installing Zellij..."

  run_as_user mkdir -p "$HOME_DIR/.local/bin"

  if [[ -x "$ZELLIJ_BIN" ]]; then
    echo "Zellij already installed."
    return
  fi

  # Not normalize_arch: zellij release assets use the raw `uname -m` names
  # (zellij-x86_64-… / zellij-aarch64-…), not Go-style amd64/arm64.
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64 | aarch64) ;;
    *) die "Unsupported architecture: $arch" ;;
  esac

  local url="https://github.com/zellij-org/zellij/releases/latest/download/zellij-${arch}-unknown-linux-musl.tar.gz"
  local tmp_dir
  tmp_dir="$(run_as_user mktemp -d "${TMPDIR:-/tmp}/glimt-zellij.XXXXXX")"

  echo "⬇️ Downloading from: $url"
  run_as_user curl -fsSL "$url" -o "$tmp_dir/zellij.tar.gz"
  run_as_user tar -xzf "$tmp_dir/zellij.tar.gz" -C "$tmp_dir"
  run_as_user install -m 0755 "$tmp_dir/zellij" "$ZELLIJ_BIN"
  run_as_user rm -rf "$tmp_dir"

  echo "Installed to $ZELLIJ_BIN"
  PATH="$HOME_DIR/.local/bin:$PATH" verify_binary zellij --version
}

config() {
  echo "Configuring Zellij theme..."
  deploy_config "$KDL_TEMPLATE" "$ZELLIJ_CONFIG_FILE"

  echo "Copying Zsh config template..."
  deploy_config "$LOCAL_CONFIG_TEMPLATE" "$ZSH_TARGET_CONFIG"
}

clean() {
  echo "Cleaning Zellij install..."

  # Use if-blocks, not `[[ ]] && rm`: a false test as the last statement would
  # return 1 and abort the caller under set -e when the file is already gone.
  if [[ -f "$ZELLIJ_BIN" ]]; then
    run_as_user rm -f "$ZELLIJ_BIN"
    echo "Removed binary: $ZELLIJ_BIN"
  fi
  # Only remove the config glimt deployed (unless the user edited it), and
  # keep any layouts/themes the user added
  if [[ -f "$ZELLIJ_CONFIG_FILE" ]]; then
    if cmp -s "$ZELLIJ_CONFIG_FILE" "$KDL_TEMPLATE"; then
      run_as_user rm -f "$ZELLIJ_CONFIG_FILE"
      echo "Removed config: $ZELLIJ_CONFIG_FILE"
    else
      echo "ℹ️  Kept edited config: $ZELLIJ_CONFIG_FILE"
    fi
  fi
  if [[ -d "$ZELLIJ_CONFIG_DIR" ]]; then
    run_as_user rmdir "$ZELLIJ_CONFIG_DIR" 2>/dev/null || true
  fi
  if [[ -f "$ZSH_TARGET_CONFIG" ]]; then
    run_as_user rm -f "$ZSH_TARGET_CONFIG"
    echo "Removed Zsh config: $ZSH_TARGET_CONFIG"
  fi
}

# === Entrypoint ===
fedora_guard

case "$ACTION" in
  deps) install_deps ;;
  install) install ;;
  config) config ;;
  clean) clean ;;
  all|"") install_deps; install; config ;;
  *) echo "Usage: $SCRIPT_NAME [deps|install|config|clean|all]"; exit 1 ;;
esac


