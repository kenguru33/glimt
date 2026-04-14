#!/usr/bin/env bash
# modules/fedora/extras/install-claude-code.sh
# Claude Code CLI — Anthropic's AI coding assistant
# Uses the official native installer (no Node.js required)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="claude-code"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"

# --- Fedora-only guard ---
if [[ -r /etc/os-release ]]; then . /etc/os-release; else die "Cannot detect OS."; fi
[[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || die "Fedora-only module."

CLAUDE_BIN="$HOME_DIR/.local/bin/claude"

# ------------------------------------------------------------
# Dependencies
# ------------------------------------------------------------
deps() {
  log "Checking dependencies..."

  if ! command -v curl >/dev/null 2>&1; then
    die "curl is required but not founsnd."
  fi

  log "Dependencies OK"
}

# ------------------------------------------------------------
# Install
# ------------------------------------------------------------
install_pkg() {
  log "Installing Claude Code via native installer..."
  run_as_user bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
  log "Claude Code installed."

  if [[ -x "$CLAUDE_BIN" ]]; then
    log "✅ claude OK"
  else
    warn "claude not found at $CLAUDE_BIN after install"
  fi
}

# ------------------------------------------------------------
# Config
# ------------------------------------------------------------
config() {
  log "No extra config needed — run 'claude' to authenticate and start using Claude Code."
}

# ------------------------------------------------------------
# Clean
# ------------------------------------------------------------
clean() {
  log "Removing Claude Code..."
  rm -f "$HOME_DIR/.local/bin/claude"
  rm -rf "$HOME_DIR/.local/share/claude"
  rm -rf "$HOME_DIR/.claude"
  rm -f "$HOME_DIR/.claude.json"
  log "Claude Code removed."
}

# ------------------------------------------------------------
# All
# ------------------------------------------------------------
all() {
  deps
  install_pkg
  config
  log "Done."
}

# ------------------------------------------------------------
# Entrypoint
# ------------------------------------------------------------
case "$ACTION" in
deps) deps ;;
install) install_pkg ;;
config) config ;;
clean) clean ;;
all) all ;;
*) die "Unknown action: $ACTION (use: all|deps|install|config|clean)" ;;
esac
