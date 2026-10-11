#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="fzf"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

LOCAL_BIN="$HOME_DIR/.local/bin"
PLUGIN_DIR="$HOME_DIR/.zsh/plugins/fzf-tab"
CONFIG_DIR="$HOME_DIR/.zsh/config"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/config/fzf.zsh"
TARGET_FILE="$CONFIG_DIR/fzf.zsh"

# === Step: deps ===
deps() {
  echo "📦 Installing fzf dependencies..."
  sudo dnf install -y fzf bat fd-find curl unzip

  echo "🛠 Ensuring $LOCAL_BIN exists..."
  run_as_user mkdir -p "$LOCAL_BIN"
}

# === Step: install ===
install() {
  echo "🔌 Installing or updating fzf-tab..."

  if [[ -d "$PLUGIN_DIR/.git" ]]; then
    echo "🔄 Updating fzf-tab..."
    run_as_user git -C "$PLUGIN_DIR" pull --quiet --rebase
    echo "✅ Updated fzf-tab"
  else
    echo "⬇️  Installing fzf-tab..."
    rm -rf "$PLUGIN_DIR"
    run_as_user mkdir -p "$(dirname "$PLUGIN_DIR")"
    run_as_user git clone --depth=1 https://github.com/Aloxaf/fzf-tab.git "$PLUGIN_DIR"
    echo "✅ Installed fzf-tab"
  fi
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

  deploy_config "$TEMPLATE_FILE" "$TARGET_FILE"
  echo "✅ Replaced $TARGET_FILE"
}

# === Step: clean ===
clean() {
  echo "🧹 Cleaning FZF setup..."

  echo "❌ Removing fzf-tab plugin"
  rm -rf "$PLUGIN_DIR"

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

