#!/usr/bin/env bash
set -Eeuo pipefail

MODULE="ssh-key"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

STATE_DIR="$HOME_DIR/.config/glimt"
GIT_STATE="$STATE_DIR/git.state"

SSH_DIR="$HOME_DIR/.ssh"
SSH_KEY="$SSH_DIR/id_ed25519"
SSH_PUB="$SSH_KEY.pub"

log() { echo "🔐 [$MODULE] $*" >&2; }

[[ -f "$GIT_STATE" ]] || {
  log "❌ Missing git state: $GIT_STATE"
  exit 2
}

# shellcheck disable=SC1090
source "$GIT_STATE"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [[ -f "$SSH_KEY" ]]; then
  log "ℹ️  SSH key already exists"
  exit 0
fi

log "🔑 Creating SSH key for $GIT_EMAIL"

ssh-keygen \
  -t ed25519 \
  -C "$GIT_EMAIL" \
  -f "$SSH_KEY" \
  -N ""

chmod 600 "$SSH_KEY"
chmod 644 "$SSH_PUB"

log "✅ SSH key created with comment: $GIT_EMAIL"
