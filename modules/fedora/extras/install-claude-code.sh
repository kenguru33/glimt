#!/usr/bin/env bash
# modules/fedora/extras/install-claude-code.sh
# Claude Code CLI — Anthropic's AI coding assistant
# Requires Node.js 18+ (provided by the volta core module)
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

VOLTA_BIN="$HOME_DIR/.volta/bin/volta"
NPM_BIN="$HOME_DIR/.volta/bin/npm"
NODE_BIN="$HOME_DIR/.volta/bin/node"

# ------------------------------------------------------------
# Dependencies
# ------------------------------------------------------------
deps() {
  log "Checking for Node.js (via Volta)..."

  if [[ ! -x "$VOLTA_BIN" ]]; then
    die "Volta not found. Run the volta module first (bash modules/fedora/install-volta.sh all)."
  fi

  if [[ ! -x "$NODE_BIN" ]]; then
    die "Node.js not found. Run: volta install node"
  fi

  local node_major
  node_major="$(run_as_user "$NODE_BIN" --version | sed 's/^v//' | cut -d. -f1)"
  if (( node_major < 18 )); then
    die "Node.js 18+ required (found v${node_major}). Run: volta install node@latest"
  fi

  log "Node.js v${node_major} OK"
}

# ------------------------------------------------------------
# Install
# ------------------------------------------------------------
install_pkg() {
  log "Installing Claude Code via npm..."
  run_as_user "$NPM_BIN" install -g @anthropic-ai/claude-code
  log "Claude Code installed."

  # Verify using the Volta-managed path
  local claude_bin="$HOME_DIR/.volta/bin/claude"
  if [[ -x "$claude_bin" ]]; then
    log "✅ claude OK"
  else
    warn "claude not found at $claude_bin after install"
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
  run_as_user "$NPM_BIN" uninstall -g @anthropic-ai/claude-code || true
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
  deps)    deps ;;
  install) install_pkg ;;
  config)  config ;;
  clean)   clean ;;
  all)     all ;;
  *)       die "Unknown action: $ACTION (use: all|deps|install|config|clean)" ;;
esac
