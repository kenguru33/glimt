#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="claude-code"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

macos_guard() {
  [[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
}

CLAUDE_BIN="$HOME_DIR/.local/bin/claude"

deps() {
  command -v curl >/dev/null 2>&1 || die "curl is required but not found."
  log "Dependencies OK"
}

install() {
  if [[ -x "$CLAUDE_BIN" ]]; then
    log "Claude Code already installed."
    return
  fi
  log "Installing Claude Code via native installer..."
  run_as_user bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
  verify_binary claude --version
}

config() { log "Run 'claude' to authenticate and start using Claude Code."; }

clean() {
  rm -f "$HOME_DIR/.local/bin/claude"
  rm -rf "$HOME_DIR/.local/share/claude"
  log "Claude Code removed."
}

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
