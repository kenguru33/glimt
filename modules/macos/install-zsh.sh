#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="zsh-env"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

PLUGIN_DIR="$HOME_DIR/.zsh/plugins"
CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSHRC_FILE="$HOME_DIR/.zshrc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSHRC_TEMPLATE="$SCRIPT_DIR/config/zshrc"

declare -A PLUGINS=(
  ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions.git"
  ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
)

write_zsh_config() {
  local name="$1" content="$2"
  local file="$CONFIG_DIR/$name.zsh"
  mkdir -p "$CONFIG_DIR"
  echo "$content" > "$file"
  log "Wrote $file"
}

deps() {
  log "Installing Zsh and git via Homebrew..."
  brew install zsh git
  mkdir -p "$HOME_DIR/.local/bin"
}

install() {
  log "Installing or updating Zsh plugins..."
  mkdir -p "$PLUGIN_DIR"

  for name in "${!PLUGINS[@]}"; do
    local repo="${PLUGINS[$name]}"
    local dir="$PLUGIN_DIR/$name"
    if [[ -d "$dir/.git" ]]; then
      log "Updating $name..."
      git -C "$dir" pull --quiet --rebase
    else
      log "Installing $name..."
      rm -rf "$dir"
      git clone --depth=1 "$repo" "$dir"
    fi
  done

  local brew_zsh
  brew_zsh="$(brew --prefix)/bin/zsh"

  # Register brew zsh in /etc/shells so chsh accepts it
  if ! grep -qF "$brew_zsh" /etc/shells; then
    log "Adding $brew_zsh to /etc/shells (requires sudo)..."
    echo "$brew_zsh" | sudo tee -a /etc/shells > /dev/null
  fi

  if [[ "$SHELL" != "$brew_zsh" ]]; then
    log "Setting default shell to $brew_zsh..."
    # Run via sudo with the username so chsh does not prompt for a password
    # interactively — that prompt is invisible under the gum spinner and hangs.
    sudo chsh -s "$brew_zsh" "$REAL_USER"
  else
    log "Zsh already default shell."
  fi
}

config() {
  log "Writing Zsh plugin configs..."
  mkdir -p "$CONFIG_DIR"

  write_zsh_config "autosuggestions" \
'[[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh'

  write_zsh_config "syntax-highlighting" \
'[[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'

  deploy_config "$SCRIPT_DIR/config/greeting.zsh" "$CONFIG_DIR/greeting.zsh"

  log "Installing .zshrc template..."
  deploy_config "$ZSHRC_TEMPLATE" "$ZSHRC_FILE"
}

clean() {
  log "Cleaning Zsh setup..."
  rm -rf "$PLUGIN_DIR" "$CONFIG_DIR" "$ZSHRC_FILE"
  log "Clean complete."
}

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
