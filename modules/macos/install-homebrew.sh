#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="homebrew"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

deps() {
  log "Checking Xcode Command Line Tools..."
  if ! xcode-select -p &>/dev/null; then
    log "Installing Xcode Command Line Tools (follow the prompt)..."
    xcode-select --install
    until xcode-select -p &>/dev/null; do sleep 5; done
  else
    log "Xcode Command Line Tools already installed."
  fi
}

install() {
  if command -v brew &>/dev/null; then
    log "Homebrew already installed at $(brew --prefix)."
    return 0
  fi
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Make brew available in the current shell for subsequent modules
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  verify_binary brew --version
}

config() {
  log "Running brew update..."
  brew update
}

clean() {
  warn "Homebrew removal is a manual step. See: https://docs.brew.sh/FAQ#how-do-i-uninstall-homebrew"
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
