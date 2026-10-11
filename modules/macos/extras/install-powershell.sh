#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="powershell"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

CASK="powershell"

macos_guard() {
  [[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
}

deps() { log "No additional dependencies."; }

# No version pin: install the cask if missing, otherwise upgrade it so every
# run (including `glimt update`) lands on the latest release.
install() {
  if brew list --cask "$CASK" &>/dev/null; then
    log "Upgrading $CASK to the latest release…"
    brew upgrade --cask "$CASK" || warn "brew upgrade --cask $CASK failed (continuing)."
  else
    brew_cask_install "$CASK"
  fi
  verify_binary pwsh --version || true
}

config() { log "No extra configuration needed."; }

clean() {
  brew uninstall --cask "$CASK" 2>/dev/null || true
}

macos_guard

case "$ACTION" in
  all)     deps; install; config ;;
  deps)    deps ;;
  install) install ;;
  config)  config ;;
  clean)   clean ;;
  *)
    echo "[$MODULE_NAME] unknown action: $ACTION" >&2
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac
