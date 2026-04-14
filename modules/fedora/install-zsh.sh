#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Zsh env setup failed. Exiting." >&2' ERR

MODULE_NAME="zsh-env"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"
PLUGIN_DIR="$HOME_DIR/.zsh/plugins"
CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSHRC_FILE="$HOME_DIR/.zshrc"
LOCAL_BIN="$HOME_DIR/.local/bin"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSHRC_TEMPLATE="$SCRIPT_DIR/config/zshrc"

declare -A PLUGINS=(
  ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions.git"
  ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
)

# === Helper: write config ===
write_zsh_config() {
  local name="$1"
  local content="$2"
  local file="$CONFIG_DIR/$name.zsh"
  mkdir -p "$CONFIG_DIR"
  echo "$content" > "$file"
  chown "$REAL_USER:$REAL_USER" "$file"
  echo "✅ Wrote $file"
}

# === Step: deps ===
deps() {
  echo "📦 Installing Zsh dependencies..."
  sudo dnf install -y zsh git

  echo "🛠 Ensuring $LOCAL_BIN exists..."
  run_as_user mkdir -p "$LOCAL_BIN"
}

# === Step: install ===
install() {
  echo "🔌 Installing or updating Zsh plugins..."
  mkdir -p "$PLUGIN_DIR"

  for name in "${!PLUGINS[@]}"; do
    repo="${PLUGINS[$name]}"
    dir="$PLUGIN_DIR/$name"

    if [[ -d "$dir/.git" ]]; then
      echo "🔄 Updating $name..."
      git -C "$dir" pull --quiet --rebase
      echo "✅ Updated $name"
    else
      echo "⬇️  Installing $name..."
      rm -rf "$dir"
      git clone --depth=1 "$repo" "$dir"
      echo "✅ Installed $name"
    fi
    chown -R "$REAL_USER:$REAL_USER" "$dir"
  done

  echo "🛠 Ensuring Zsh is default shell for $REAL_USER..."
  if [[ "$(getent passwd "$REAL_USER" | cut -d: -f7)" != "$(command -v zsh)" ]]; then
    sudo chsh -s "$(command -v zsh)" "$REAL_USER"
    echo "✅ Default shell set to Zsh"
  else
    echo "⏭️  Zsh already default shell"
  fi
}

# === Step: config ===
config() {
  echo "🔧 Writing Zsh plugin configs..."

  mkdir -p "$CONFIG_DIR"

  write_zsh_config "autosuggestions" \
'[[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh'

  write_zsh_config "syntax-highlighting" \
'[[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'

  echo "🔧 Installing .zshrc template..."

  if [[ -f "$ZSHRC_FILE" ]]; then
    backup="$ZSHRC_FILE.backup.$(date +%Y%m%d%H%M%S)"
    cp "$ZSHRC_FILE" "$backup"
    echo "💾 Backed up existing .zshrc to $backup"
  fi

  cp "$ZSHRC_TEMPLATE" "$ZSHRC_FILE"
  chown "$REAL_USER:$REAL_USER" "$ZSHRC_FILE"
  echo "✅ Installed new .zshrc"
}

# === Step: clean ===
clean() {
  echo "🧹 Cleaning Zsh setup..."

  echo "❌ Removing plugins from $PLUGIN_DIR"
  rm -rf "$PLUGIN_DIR"

  echo "❌ Removing Zsh config files"
  rm -rf "$CONFIG_DIR"

  echo "❌ Removing .zshrc"
  rm -f "$ZSHRC_FILE"

  echo "✅ Clean complete."
}

# === Entry Point ===
case "$ACTION" in
  all)    deps; install; config ;;
  deps)   deps ;;
  install) install ;;
  config) config ;;
  clean)  clean ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

