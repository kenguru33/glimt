#!/usr/bin/env bash
# Glimt module: eza (modern ls replacement)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ eza module failed at line $LINENO" >&2' ERR

MODULE_NAME="eza"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

# --------------------------------------------------
# Homebrew (canonical Silverblue location)
# --------------------------------------------------
BREW_PREFIX="/var/home/linuxbrew/.linuxbrew"
BREW_BIN="$BREW_PREFIX/bin/brew"

ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSH_FILE="$ZSH_CONFIG_DIR/eza.zsh"

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
# Homebrew check (simple + reliable)
# --------------------------------------------------
check_brew() {
  if [[ -x "$BREW_BIN" ]]; then
    eval "$("$BREW_BIN" shellenv)"
    return 0
  fi

  log "❌ Homebrew not found at $BREW_BIN"
  log "ℹ Ensure install-silverblue-basics.sh has completed successfully"
  return 1
}

# --------------------------------------------------
# deps
# --------------------------------------------------
deps() {
  log "Checking Homebrew availability"
  check_brew
}

# --------------------------------------------------
# install
# --------------------------------------------------
install() {
  require_user
  check_brew

  log "Installing eza via Homebrew"

  if brew list eza &>/dev/null; then
    log "eza already installed – upgrading"
    brew upgrade eza || true
  else
    brew install eza
  fi

  command -v eza >/dev/null || {
    log "❌ eza command not found after installation"
    exit 1
  }

  log "eza ready: $(command -v eza)"
}

# --------------------------------------------------
# config
# --------------------------------------------------
config() {
  require_user
  check_brew

  command -v eza >/dev/null || {
    log "❌ eza not installed; run install first"
    exit 1
  }

  log "Writing Zsh aliases"

  mkdir -p "$ZSH_CONFIG_DIR"
  cat >"$ZSH_FILE" <<'EOF'
# eza – modern ls replacement
if command -v eza &>/dev/null; then
  alias ls='eza --group-directories-first --icons=auto'
  alias ll='eza -l --group-directories-first --icons=auto'
  alias la='eza -la --group-directories-first --icons=auto'
  alias lt='eza -T --group-directories-first --icons=auto'
fi
EOF

  chown "$REAL_USER:$REAL_USER" "$ZSH_FILE"
  log "Zsh config installed at $ZSH_FILE"
}

# --------------------------------------------------
# clean
# --------------------------------------------------
clean() {
  require_user

  log "Removing eza config"
  rm -f "$ZSH_FILE"

  if check_brew && brew list eza &>/dev/null; then
    log "Uninstalling eza"
    brew uninstall eza
  fi

  log "Clean complete"
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

exit 0
