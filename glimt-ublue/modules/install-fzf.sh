#!/usr/bin/env bash
# Glimt module: fzf (fuzzy finder + fzf-tab)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ fzf module failed at line $LINENO" >&2' ERR

MODULE_NAME="fzf"
ACTION="${1:-all}"

# --------------------------------------------------
# User context
# --------------------------------------------------
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
BREW_PREFIX="$HOME_DIR/.linuxbrew"

# --------------------------------------------------
# Zsh paths
# --------------------------------------------------
ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSH_FILE="$ZSH_CONFIG_DIR/fzf.zsh"
ZSH_PLUGIN_DIR="$HOME_DIR/.zsh/plugins"
FZF_TAB_DIR="$ZSH_PLUGIN_DIR/fzf-tab"

# --------------------------------------------------
# Logging helpers
# --------------------------------------------------
log() {
  printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2
}

require_user() {
  if [[ "$EUID" -eq 0 && -z "${SUDO_USER:-}" ]]; then
    echo "❌ Do not run this module as root directly." >&2
    exit 1
  fi
}

# --------------------------------------------------
# Homebrew detection
# --------------------------------------------------
check_brew() {
  if command -v brew &>/dev/null; then
    return 0
  fi

  local possible_paths=(
    "$BREW_PREFIX/bin/brew"
    "$HOME_DIR/.linuxbrew/bin/brew"
    "/home/linuxbrew/.linuxbrew/bin/brew"
  )

  for path in "${possible_paths[@]}"; do
    if [[ -x "$path" ]]; then
      BREW_PREFIX="$(dirname "$(dirname "$path")")"
      eval "$("$path" shellenv)" >/dev/null 2>&1 || true
      export PATH="$BREW_PREFIX/bin:$BREW_PREFIX/sbin:$PATH"
      return 0
    fi
  done

  log "❌ Homebrew not found"
  return 1
}

# --------------------------------------------------
# Actions
# --------------------------------------------------
deps() {
  log "📦 Checking Homebrew..."
  check_brew || exit 1
  log "✅ Homebrew available"
}

install() {
  require_user
  check_brew || exit 1

  log "⬇️  Installing fzf..."
  if brew list fzf &>/dev/null; then
    brew upgrade fzf
  else
    brew install fzf
  fi

  command -v fzf &>/dev/null || {
    log "❌ fzf binary not found after install"
    exit 1
  }

  log "🔌 Installing fzf-tab plugin..."
  mkdir -p "$ZSH_PLUGIN_DIR"

  if [[ ! -d "$FZF_TAB_DIR" ]]; then
    git clone https://github.com/Aloxaf/fzf-tab "$FZF_TAB_DIR"
    log "✅ fzf-tab installed"
  else
    log "🔄 fzf-tab already installed"
  fi
}

config() {
  require_user

  log "🔧 Configuring fzf + fzf-tab..."
  mkdir -p "$ZSH_CONFIG_DIR"

  cat >"$ZSH_FILE" <<'EOF'
# --------------------------------------------------
# fzf + fzf-tab configuration (Glimt)
# --------------------------------------------------

# Initialize completion FIRST
autoload -Uz compinit
compinit

# --------------------------------------------------
# fzf-tab (must load AFTER compinit)
# --------------------------------------------------
if [[ -f ~/.zsh/plugins/fzf-tab/fzf-tab.plugin.zsh ]]; then
  source ~/.zsh/plugins/fzf-tab/fzf-tab.plugin.zsh
fi

# --------------------------------------------------
# fzf defaults
# --------------------------------------------------
if command -v fd &>/dev/null; then
  export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
else
  export FZF_DEFAULT_COMMAND='find . -type f -not -path "*/\.git/*"'
fi

export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

# --------------------------------------------------
# fzf keybindings ONLY (safe with fzf-tab)
# --------------------------------------------------
if command -v brew &>/dev/null; then
  FZF_KEYS="$(brew --prefix)/opt/fzf/shell/key-bindings.zsh"
  [[ -f "$FZF_KEYS" ]] && source "$FZF_KEYS"
fi

# --------------------------------------------------
# fzf-tab behavior
# --------------------------------------------------
zstyle ':completion:*' menu no
zstyle ':fzf-tab:*' switch-group ',' '.'
zstyle ':fzf-tab:*' fzf-command fzf
zstyle ':fzf-tab:*' accept-line enter

# Preview files with bat if available
if command -v bat &>/dev/null; then
  zstyle ':fzf-tab:complete:*:*' fzf-preview \
    '[[ -f $realpath ]] && bat --style=numbers --color=always $realpath || ls -la $realpath'
fi
EOF

  log "✅ Zsh config written: $ZSH_FILE"
}

clean() {
  require_user

  log "🧹 Cleaning fzf setup..."

  [[ -f "$ZSH_FILE" ]] && rm -f "$ZSH_FILE"
  [[ -d "$FZF_TAB_DIR" ]] && rm -rf "$FZF_TAB_DIR"

  if check_brew && brew list fzf &>/dev/null; then
    brew uninstall fzf
  fi

  log "✅ Clean complete"
}

# --------------------------------------------------
# Entry point
# --------------------------------------------------
case "$ACTION" in
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
all)
  deps
  install
  config
  ;;
*)
  echo "Usage: $0 {all|deps|install|config|clean}"
  exit 1
  ;;
esac
