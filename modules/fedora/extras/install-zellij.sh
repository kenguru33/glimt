#!/bin/bash
set -e
trap 'echo "❌ Something went wrong. Exiting." >&2' ERR

# === Metadata ===
MODULE_NAME="zellij"
SCRIPT_NAME="install-zellij.sh"
ACTION="${1:-all}"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
ZELLIJ_CONFIG_DIR="$HOME_DIR/.config/zellij"
ZELLIJ_CONFIG_FILE="$ZELLIJ_CONFIG_DIR/config.kdl"
ZELLIJ_BIN="$HOME_DIR/.local/bin/zellij"
ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
LOCAL_CONFIG_TEMPLATE="$(dirname "$0")/../config/zellij.zsh"
ZSH_TARGET_CONFIG="$ZSH_CONFIG_DIR/zellij.zsh"

# === OS Check ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "❌ This script only supports Fedora/RHEL."
  exit 1
fi

# === Dependencies ===
DEPS=(curl tar wl-clipboard)

install_deps() {
  echo "📦 Installing dependencies..."
  sudo dnf makecache -y
  sudo dnf install -y "${DEPS[@]}"
}

install() {
  echo "📦 Installing Zellij..."

  mkdir -p "$HOME_DIR/.local/bin"

  if [[ -x "$ZELLIJ_BIN" ]]; then
    echo "✔️ Zellij already installed."
    return
  fi

  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="x86_64" ;;
    aarch64) ARCH="aarch64" ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
  esac

  echo "🌐 Fetching latest Zellij release..."
  URL=$(curl -s https://api.github.com/repos/zellij-org/zellij/releases/latest \
    | grep "browser_download_url" \
    | grep "linux-${ARCH}.tar.gz" \
    | cut -d '"' -f 4)

  if [[ -z "$URL" ]]; then
    echo "⚠️ GitHub API failed. Falling back to v0.39.2..."
    URL="https://github.com/zellij-org/zellij/releases/download/v0.39.2/zellij-${ARCH}-unknown-linux-musl.tar.gz"
  fi

  echo "⬇️ Downloading from: $URL"
  curl -Lo /tmp/zellij.tar.gz "$URL"
  tar -xzf /tmp/zellij.tar.gz -C /tmp
  mv /tmp/zellij "$ZELLIJ_BIN"
  chmod +x "$ZELLIJ_BIN"

  echo "✅ Installed to $ZELLIJ_BIN"
}

config() {
  echo "⚙️ Configuring Zellij theme..."
  mkdir -p "$ZELLIJ_CONFIG_DIR"

  cat > "$ZELLIJ_CONFIG_FILE" <<EOF
theme "catppuccin-mocha"

themes {
  catppuccin-mocha {
    fg "#cdd6f4"
    bg "#1e1e2e"
    black "#45475a"
    red "#f38ba8"
    green "#a6e3a1"
    yellow "#f9e2af"
    blue "#89b4fa"
    magenta "#f5c2e7"
    cyan "#94e2d5"
    white "#bac2de"
    orange "#fab387"
  }
}

default_layout "compact"
default_mode "normal"

copy_on_select true                 // selecting text copies immediately
copy_clipboard "system"             // use system clipboard (not PRIMARY)
copy_command "wl-copy"              // how to copy on Wayland
paste_command "wl-paste --no-newline"
mouse_mode true                     // keep mouse features in panes




EOF

  echo "✅ Theme written to $ZELLIJ_CONFIG_FILE"

  echo "📁 Copying Zsh config template..."
  mkdir -p "$ZSH_CONFIG_DIR"
  cp "$LOCAL_CONFIG_TEMPLATE" "$ZSH_TARGET_CONFIG"
  echo "✅ Copied: $LOCAL_CONFIG_TEMPLATE → $ZSH_TARGET_CONFIG"
}

clean() {
  echo "🧹 Cleaning Zellij install..."

  [[ -f "$ZELLIJ_BIN" ]] && rm -f "$ZELLIJ_BIN" && echo "🗑️ Removed binary: $ZELLIJ_BIN"
  [[ -d "$ZELLIJ_CONFIG_DIR" ]] && rm -rf "$ZELLIJ_CONFIG_DIR" && echo "🗑️ Removed config: $ZELLIJ_CONFIG_DIR"
  [[ -f "$ZSH_TARGET_CONFIG" ]] && rm -f "$ZSH_TARGET_CONFIG" && echo "🗑️ Removed Zsh config: $ZSH_TARGET_CONFIG"
}

# === Entrypoint ===
case "$ACTION" in
  deps) install_deps ;;
  install) install ;;
  config) config ;;
  clean) clean ;;
  all|"") install_deps; install; config ;;
  *) echo "Usage: $SCRIPT_NAME [deps|install|config|clean|all]"; exit 1 ;;
esac


