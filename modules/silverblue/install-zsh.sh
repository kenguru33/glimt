#!/bin/bash
set -e
trap 'echo "❌ Zsh env setup failed. Exiting." >&2' ERR

MODULE_NAME="zsh-env"
ACTION="${1:-all}"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
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
  echo "$content" >"$file"
  chown "$REAL_USER:$REAL_USER" "$file"
  echo "✅ Wrote $file"
}

# === Step: deps ===
deps() {
  # Check if zsh is available (should be installed via rpm-ostree in prereq module)
  if command -v zsh &>/dev/null 2>&1; then
    echo "✅ zsh is available: $(command -v zsh)"
  elif rpm -q zsh &>/dev/null 2>&1; then
    echo "⚠️  zsh package is installed but not yet in PATH (reboot may be required)"
  else
    echo "⚠️  zsh is not installed. Please install it via the prereq module first."
  fi
  echo "🛠 Ensuring $LOCAL_BIN exists..."
  mkdir -p "$LOCAL_BIN"
  chown "$REAL_USER:$REAL_USER" "$LOCAL_BIN"
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

  echo "🛠 Ensuring Zsh is default shell..."
  local zsh_path
  zsh_path=$(command -v zsh 2>/dev/null || echo "")
  
  if [[ -z "$zsh_path" ]]; then
    # Try to find zsh in common locations if not in PATH
    if [[ -x /usr/bin/zsh ]]; then
      zsh_path="/usr/bin/zsh"
    elif [[ -x /bin/zsh ]]; then
      zsh_path="/bin/zsh"
    elif rpm -q zsh &>/dev/null 2>&1; then
      # Package is installed but not in PATH yet (likely needs reboot)
      echo "⚠️  zsh package is installed but not yet in PATH"
      echo "ℹ️  Shell will be changed after reboot when zsh becomes available"
      return 0
    else
      echo "❌ zsh is not installed. Please install it via the prereq module first."
      return 1
    fi
  fi
  
  local current_shell
  current_shell=$(getent passwd "$REAL_USER" | cut -d: -f7)
  
  if [[ "$current_shell" != "$zsh_path" ]]; then
    # Change shell for the current user (no sudo needed for own shell)
    chsh -s "$zsh_path"
    echo "✅ Default shell set to Zsh: $zsh_path"
  else
    echo "⏭️  Zsh already default shell: $zsh_path"
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
all)
  deps
  install
  config
  ;;
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
*)
  echo "❌ Unknown action: $ACTION"
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac
