#!/bin/bash
set -e
trap 'echo "❌ FZF install failed. Exiting." >&2' ERR

MODULE_NAME="fzf"
ACTION="${1:-all}"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
LOCAL_BIN="$HOME_DIR/.local/bin"
PLUGIN_DIR="$HOME_DIR/.zsh/plugins/fzf-tab"
CONFIG_DIR="$HOME_DIR/.zsh/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/config/fzf.zsh"
TARGET_FILE="$CONFIG_DIR/fzf.zsh"

# === Step: deps ===
deps() {
  echo "📦 Installing fzf dependencies..."
  sudo apt update
  sudo apt install -y fzf bat fd-find curl unzip

  echo "🛠 Ensuring $LOCAL_BIN exists..."
  mkdir -p "$LOCAL_BIN"
  chown "$REAL_USER:$REAL_USER" "$LOCAL_BIN"

  # Symlink fdfind → fd
  if command -v fdfind >/dev/null && ! command -v fd >/dev/null; then
    ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"
    echo "✅ Linked fdfind → fd"
  fi

  # Symlink batcat → bat
  if command -v batcat >/dev/null && ! command -v bat >/dev/null; then
    ln -sf "$(command -v batcat)" "$LOCAL_BIN/bat"
    echo "✅ Linked batcat → bat"
  fi
}

# === Step: install ===
install() {
  echo "🔌 Installing or updating fzf-tab..."

  if [[ -d "$PLUGIN_DIR/.git" ]]; then
    echo "🔄 Updating fzf-tab..."
    git -C "$PLUGIN_DIR" pull --quiet --rebase
    echo "✅ Updated fzf-tab"
  else
    echo "⬇️  Installing fzf-tab..."
    rm -rf "$PLUGIN_DIR"
    git clone --depth=1 https://github.com/Aloxaf/fzf-tab.git "$PLUGIN_DIR"
    echo "✅ Installed fzf-tab"
  fi

  chown -R "$REAL_USER:$REAL_USER" "$PLUGIN_DIR"
}

# === Step: config ===
config() {
  echo "♻️ Replacing fzf.zsh config from template..."

  echo "🔍 Template: $TEMPLATE_FILE"
  echo "📁 Target:   $TARGET_FILE"

  if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "❌ Template file not found: $TEMPLATE_FILE"
    exit 1
  fi

  mkdir -p "$CONFIG_DIR"
  cp "$TEMPLATE_FILE" "$TARGET_FILE"
  chown "$REAL_USER:$REAL_USER" "$TARGET_FILE"
  echo "✅ Replaced $TARGET_FILE"
}

# === Step: clean ===
clean() {
  echo "🧹 Cleaning FZF setup..."

  echo "❌ Removing fzf-tab plugin"
  rm -rf "$PLUGIN_DIR"

  echo "❌ Removing symlinks for fd and bat"
  rm -f "$LOCAL_BIN/fd" "$LOCAL_BIN/bat"

  echo "❌ Removing fzf.zsh config"
  rm -f "$TARGET_FILE"

  echo "✅ Clean complete."
}

# === Entry Point ===
case "$ACTION" in
  all)     deps; install; config ;;
  deps)    deps ;;
  install) install ;;
  config)  config ;;
  clean)   clean ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac
