#!/bin/bash
set -e
trap 'echo "❌ Something went wrong. Exiting." >&2' ERR

# === Metadata ===
MODULE_NAME="zellij"
SCRIPT_NAME="install-zellij.sh"
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZELLIJ_CONFIG_DIR="$HOME/.config/zellij"
ZELLIJ_CONFIG_FILE="$ZELLIJ_CONFIG_DIR/config.kdl"
ZELLIJ_BIN="$HOME/.local/bin/zellij"
ZSHRC_FILE="$HOME/.zshrc"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Could not detect OS."
  exit 1
fi

# === Dependencies ===
DEPS_DEBIAN=(curl tar)
DEPS_FEDORA=(curl tar)

install_deps() {
  echo "📦 Installing dependencies for $OS_ID..."

  case "$OS_ID" in
    debian|ubuntu)
      sudo apt update
      sudo apt install -y "${DEPS_DEBIAN[@]}"
      ;;
    fedora)
      sudo dnf install -y "${DEPS_FEDORA[@]}"
      ;;
    *)
      echo "❌ Unsupported OS: $OS_ID"
      exit 1
      ;;
  esac
}

# === Install Zellij from GitHub ===
install() {
  echo "📦 Installing Zellij..."

  mkdir -p ~/.local/bin

  if command -v zellij >/dev/null || [[ -x "$ZELLIJ_BIN" ]]; then
    echo "✔️ Zellij already installed."
    return
  fi

  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64) ARCH="x86_64" ;;
    aarch64) ARCH="aarch64" ;;
    *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
  esac

  echo "🌐 Fetching latest release URL from GitHub..."
  URL=$(curl -s https://api.github.com/repos/zellij-org/zellij/releases/latest \
    | grep "browser_download_url" \
    | grep "linux-${ARCH}.tar.gz" \
    | cut -d '"' -f 4)

  if [[ -z "$URL" ]]; then
    echo "⚠️ GitHub API failed. Falling back to v0.39.2..."
    URL="https://github.com/zellij-org/zellij/releases/download/v0.39.2/zellij-${ARCH}-unknown-linux-musl.tar.gz"
  fi

  echo "⬇️ Downloading Zellij from: $URL"
  curl -Lo /tmp/zellij.tar.gz "$URL"
  tar -xzf /tmp/zellij.tar.gz -C /tmp
  mv /tmp/zellij "$ZELLIJ_BIN"
  chmod +x "$ZELLIJ_BIN"

  echo "✅ Zellij installed to $ZELLIJ_BIN"
  echo "👉 Make sure $HOME/.local/bin is in your PATH"
}

# === Configure Zellij with Catppuccin Mocha theme ===
config() {
  echo "⚙️ Writing Zellij config..."
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
EOF

  echo "✅ Zellij theme set to Catppuccin Mocha"

  local path_line='export PATH="$HOME/.local/bin:$PATH"'
  local path_comment='# Add local bin to PATH'
  local autostart_marker='# === Auto-start Zellij'

  # Ensure PATH line exists first
  if ! grep -Fxq "$path_line" "$ZSHRC_FILE"; then
    echo "🔧 Adding ~/.local/bin to PATH in $ZSHRC_FILE"
    echo "" >> "$ZSHRC_FILE"
    echo "$path_comment" >> "$ZSHRC_FILE"
    echo "$path_line" >> "$ZSHRC_FILE"
  fi

  # Add Zellij autostart only if not already present
  if ! grep -q "$autostart_marker" "$ZSHRC_FILE"; then
    echo "🔧 Adding Zellij autostart to $ZSHRC_FILE"
    echo "" >> "$ZSHRC_FILE"
    cat >> "$ZSHRC_FILE" <<'EORC'
# === Auto-start Zellij if not already inside ===
if [ -z "$ZELLIJ" ] && [ -z "$TMUX" ] && [ -n "$PS1" ] && [ -t 1 ]; then
  command -v zellij >/dev/null && exec zellij
fi
EORC
    echo "✅ Zellij autostart added to $ZSHRC_FILE"
  else
    echo "ℹ️ Zellij autostart already present in $ZSHRC_FILE"
  fi
}

# === Clean config and binary ===
clean() {
  echo "🧹 Removing Zellij config and binary..."

  [[ -d "$ZELLIJ_CONFIG_DIR" ]] && rm -rf "$ZELLIJ_CONFIG_DIR" && echo "🗑️ Removed config: $ZELLIJ_CONFIG_DIR"
  [[ -f "$ZELLIJ_BIN" ]] && rm -f "$ZELLIJ_BIN" && echo "🗑️ Removed binary: $ZELLIJ_BIN"

  if grep -q "# === Auto-start Zellij" "$ZSHRC_FILE"; then
    sed -i '/# === Auto-start Zellij/,/fi/d' "$ZSHRC_FILE"
    echo "🗑️ Removed Zellij autostart from $ZSHRC_FILE"
  fi
}

# === Entry Point ===
case "$1" in
  deps) install_deps ;;
  install) install ;;
  config) config ;;
  clean) clean ;;
  all|"")
    install_deps
    install
    config
    ;;
  *)
    echo "Usage: $SCRIPT_NAME [deps|install|config|clean|all]"
    exit 1
    ;;
esac
