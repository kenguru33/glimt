#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Zsh env setup failed at line $LINENO" >&2' ERR

MODULE_NAME="zsh-env"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

PLUGIN_DIR="$HOME_DIR/.zsh/plugins"
CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSHRC_FILE="$HOME_DIR/.zshrc"
LOCAL_BIN="$HOME_DIR/.local/bin"

# --------------------------------------------------
# Resolve repo root (modules/ → repo/)
# --------------------------------------------------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
MODULES_DIR="$(dirname "$SCRIPT_PATH")"
REPO_ROOT="$(dirname "$MODULES_DIR")"

ZSHRC_TEMPLATE="$REPO_ROOT/config/zshrc"

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
  printf '%s\n' "$content" >"$file"
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
    log "⚠️  zsh installed but pending (reboot required)"
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
  log "Installing / updating Zsh plugins"
  mkdir -p "$PLUGIN_DIR"

  for name in "${!PLUGINS[@]}"; do
    repo="${PLUGINS[$name]}"
    dir="$PLUGIN_DIR/$name"

    if [[ -d "$dir/.git" ]]; then
      log "Updating $name"
      git -C "$dir" pull --quiet --rebase
    else
      log "Installing $name"
      rm -rf "$dir"
      git clone --depth=1 "$repo" "$dir"
    fi

    chown -R "$REAL_USER:$REAL_USER" "$dir"
  done

  # --------------------------------------------------
  # Schedule shell change when Fedora zsh becomes available
  # (rpm-ostree pending → after reboot)
  # --------------------------------------------------
  log "Scheduling one-shot default shell change to /usr/bin/zsh"

  sudo systemd-run \
    --unit=set-default-shell-zsh \
    --description="Set default shell to zsh for $REAL_USER" \
    --property=Type=oneshot \
    --property=ConditionPathExists=/usr/bin/zsh \
    /usr/sbin/usermod -s /usr/bin/zsh "$REAL_USER"

  log "ℹ️  Default shell will be set automatically after zsh is available"
}

# --------------------------------------------------
# Step: config
# --------------------------------------------------
config() {
  log "Writing Zsh plugin configs"

  write_zsh_config "autosuggestions" \
    '[[ -f ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source ~/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh'

  write_zsh_config "syntax-highlighting" \
    '[[ -f ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source ~/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'

  log "Installing .zshrc template"

  [[ -f "$ZSHRC_TEMPLATE" ]] || {
    echo "❌ Missing template: $ZSHRC_TEMPLATE" >&2
    exit 1
  }

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
  log "Cleaning Zsh environment"

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

exit 0
