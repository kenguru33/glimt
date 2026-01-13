#!/usr/bin/env bash
set -Eeuo pipefail
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

log() { echo "🔧 [$MODULE_NAME] $*"; }

# --------------------------------------------------
# Helper: write config snippet
# --------------------------------------------------
write_zsh_config() {
  local name="$1"
  local content="$2"
  local file="$CONFIG_DIR/$name.zsh"

  mkdir -p "$CONFIG_DIR"
  echo "$content" >"$file"
  chown "$REAL_USER:$REAL_USER" "$file"
  log "Wrote $file"
}

# --------------------------------------------------
# Step: deps
# --------------------------------------------------
deps() {
  if command -v zsh &>/dev/null; then
    log "zsh available: $(command -v zsh)"
  elif rpm -q zsh &>/dev/null; then
    log "⚠️  zsh installed but not yet active (reboot may be required)"
  else
    log "⚠️  zsh not installed (handled by prereq module)"
  fi

  mkdir -p "$LOCAL_BIN"
  chown "$REAL_USER:$REAL_USER" "$LOCAL_BIN"
}

# --------------------------------------------------
# Step: install
# --------------------------------------------------
install() {
  log "Installing / updating Zsh plugins..."
  mkdir -p "$PLUGIN_DIR"

  for name in "${!PLUGINS[@]}"; do
    repo="${PLUGINS[$name]}"
    dir="$PLUGIN_DIR/$name"

    if [[ -d "$dir/.git" ]]; then
      log "Updating $name..."
      git -C "$dir" pull --quiet --rebase
    else
      log "Installing $name..."
      rm -rf "$dir"
      git clone --depth=1 "$repo" "$dir"
    fi

    chown -R "$REAL_USER:$REAL_USER" "$dir"
  done

  # --------------------------------------------------
# Set Zsh as default shell (SAFE, NON-BLOCKING)
# --------------------------------------------------
zsh_path="$(command -v zsh 2>/dev/null || true)"
[[ -z "$zsh_path" && -x /usr/bin/zsh ]] && zsh_path="/usr/bin/zsh"

if [[ -n "$zsh_path" ]]; then
  current_shell="$(getent passwd "$REAL_USER" | cut -d: -f7)"

  if [[ "$current_shell" == "$zsh_path" ]]; then
    log "Zsh already default shell: $zsh_path"
  else
    log "Requesting default shell change to Zsh (non-blocking)..."

    (
      # Detach completely from TTY and stdin
      exec </dev/null >/dev/null 2>&1

      # Hard timeout: if this hangs, it dies
      timeout 5s sudo -n usermod -s "$zsh_path" "$REAL_USER"
    ) &

    log "ℹ️  Shell change requested in background"
    log "👉 If it does not take effect, run manually:"
    log "   sudo usermod -s $zsh_path $REAL_USER"
  fi
fi

}

# --------------------------------------------------
# Step: config
# --------------------------------------------------
config() {
  log "Writing Zsh plugin configs..."

  write_zsh_config "autosuggestions" \
    '[[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh'

  write_zsh_config "syntax-highlighting" \
    '[[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'

  log "Installing .zshrc template..."

  if [[ -f "$ZSHRC_FILE" ]]; then
    backup="$ZSHRC_FILE.backup.$(date +%Y%m%d%H%M%S)"
    cp "$ZSHRC_FILE" "$backup"
    log "Backed up existing .zshrc → $backup"
  fi

  cp "$ZSHRC_TEMPLATE" "$ZSHRC_FILE"
  chown "$REAL_USER:$REAL_USER" "$ZSHRC_FILE"
  log "Installed new .zshrc"
}

# --------------------------------------------------
# Step: clean
# --------------------------------------------------
clean() {
  log "Cleaning Zsh environment..."

  rm -rf "$PLUGIN_DIR"
  rm -rf "$CONFIG_DIR"
  rm -f "$ZSHRC_FILE"

  log "Zsh cleanup complete"
}

# --------------------------------------------------
# Entry point
# --------------------------------------------------
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
    echo "Usage: $0 {all|deps|install|config|clean}"
    exit 1
    ;;
esac
