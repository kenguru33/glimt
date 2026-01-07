#!/usr/bin/env bash
# Glimt module: Silverblue prereq
#
# Exit codes:
#   0 = success
#   2 = controlled stop (sudo required OR reboot required)
#   1 = real failure

set -Eeuo pipefail
log() { echo "[prereq] $*" >&2; }

# --------------------------------------------------
# Resolve module root (RELATIVE, NEVER hardcoded)
# --------------------------------------------------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
SILVERBLUE_DIR="$(dirname "$SCRIPT_DIR")"

# SILVERBLUE_DIR now points to:
# ~/.glimt/modules/silverblue

# --------------------------------------------------
# Paths / state
# --------------------------------------------------
HOME_DIR="$HOME"
STATE_DIR="$HOME_DIR/.config/glimt"
mkdir -p "$STATE_DIR"

GIT_STATE_FILE="$STATE_DIR/git.state"

# Homebrew
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
BREW_BIN="$BREW_PREFIX/bin/brew"

# --------------------------------------------------
# Sudo guard (handled by orchestrator)
# --------------------------------------------------
sudo -n true 2>/dev/null || exit 2

# --------------------------------------------------
# STEP 0 — Git identity (ONCE)
# --------------------------------------------------
if [[ ! -f "$GIT_STATE_FILE" ]]; then
  [[ -t 0 ]] || exit 2

  while true; do
    read -rp "👉 Git full name: " GIT_NAME
    [[ -n "$GIT_NAME" ]] && break
    echo "❌ Name cannot be empty"
  done

  while true; do
    read -rp "👉 Git email: " GIT_EMAIL
    [[ "$GIT_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]] && break
    echo "❌ Invalid email"
  done

  read -rp "👉 Git editor [nvim]: " GIT_EDITOR
  GIT_EDITOR="${GIT_EDITOR:-nvim}"

  cat >"$GIT_STATE_FILE" <<EOF
GIT_NAME="$GIT_NAME"
GIT_EMAIL="$GIT_EMAIL"
GIT_EDITOR="$GIT_EDITOR"
GIT_BRANCH="main"
GIT_REBASE="true"
EOF

  log "💾 Git identity saved"
fi

# --------------------------------------------------
# STEP 0b — Apply git config (RELATIVE PATH)
# --------------------------------------------------
GIT_CONFIG_SCRIPT="$SILVERBLUE_DIR/install-git-config.sh"

if [[ ! -x "$GIT_CONFIG_SCRIPT" ]]; then
  log "❌ Git config script not found:"
  log "   $GIT_CONFIG_SCRIPT"
  exit 1
fi

log "🔧 Applying Git configuration"
bash "$GIT_CONFIG_SCRIPT" all

# --------------------------------------------------
# rpm-ostree base packages
# --------------------------------------------------
sudo -n rpm-ostree install -y --allow-inactive \
  curl git file jq zsh wl-clipboard || true

# --------------------------------------------------
# Reboot detection
# --------------------------------------------------
rpm-ostree status | grep -q "pending deployment" && exit 2

# --------------------------------------------------
# Homebrew (Linux prefix)
# --------------------------------------------------
if [[ ! -x "$BREW_BIN" ]]; then
  NONINTERACTIVE=1 \
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

[[ -x "$BREW_BIN" ]] || exit 1
exit 0
