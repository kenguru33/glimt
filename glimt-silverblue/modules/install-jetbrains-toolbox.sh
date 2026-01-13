#!/usr/bin/env bash
# Glimt module: jetbrains-toolbox
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ jetbrains-toolbox module failed at line $LINENO" >&2' ERR

MODULE_NAME="jetbrains-toolbox"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

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
# Homebrew detection (Silverblue-safe)
# --------------------------------------------------
check_brew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  local brew_bin="/var/home/linuxbrew/.linuxbrew/bin/brew"
  if [[ -x "$brew_bin" ]]; then
    eval "$("$brew_bin" shellenv)"
    return 0
  fi

  log "❌ Homebrew not found"
  log "👉 Run install-basic / prereq module first"
  return 1
}

# --------------------------------------------------
deps() {
  require_user
  log "📦 Checking dependencies..."

  check_brew

  log "✅ Homebrew available"
}

# --------------------------------------------------
install() {
  require_user
  check_brew

  log "📦 Installing JetBrains Toolbox via Homebrew..."

  if brew list --cask jetbrains-toolbox >/dev/null 2>&1; then
    log "🔄 JetBrains Toolbox already installed – upgrading"
    brew upgrade --cask jetbrains-toolbox || true
  else
    brew install --cask jetbrains-toolbox
  fi

  log "✅ JetBrains Toolbox installed"
}

# --------------------------------------------------
config() {
  require_user

  log "ℹ️ No additional configuration required"
  log "👉 Toolbox manages desktop files, icons, and updates itself"
}

# --------------------------------------------------
clean() {
  require_user
  check_brew || true

  log "🧹 Removing JetBrains Toolbox..."

  if brew list --cask jetbrains-toolbox >/dev/null 2>&1; then
    brew uninstall --cask jetbrains-toolbox
    log "✅ JetBrains Toolbox removed"
  else
    log "ℹ️ JetBrains Toolbox not installed"
  fi
}

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
