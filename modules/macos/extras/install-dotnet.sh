#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="dotnet"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

macos_guard() {
  [[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
}

deps() { log "No additional dependencies."; }

install() {
  if brew list dotnet &>/dev/null; then
    log "dotnet already installed."
  else
    log "Installing dotnet via Homebrew..."
    brew install dotnet
  fi
  verify_binary dotnet --version
}

config() { log "No configuration needed."; }

clean() { brew uninstall dotnet 2>/dev/null || true; }

macos_guard

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
