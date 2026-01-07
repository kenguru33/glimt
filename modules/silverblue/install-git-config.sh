#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Git config setup failed at line $LINENO" >&2' ERR

MODULE_NAME="git-config"
ACTION="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------
# Paths / user context
# ---------------------------------------------------------------------
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

STATE_DIR="$HOME_DIR/.config/glimt"
GIT_STATE_FILE="$STATE_DIR/git.state"

ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSH_TARGET_FILE="$ZSH_CONFIG_DIR/git.zsh"
PLUGIN_DIR="$HOME_DIR/.zsh/plugins/git"
FALLBACK_COMPLETION="$PLUGIN_DIR/git-completion.zsh"
TEMPLATE_FILE="$SCRIPT_DIR/config/git.zsh"

log() { echo "🔧 [$MODULE_NAME] $*"; }
die() { echo "❌ [$MODULE_NAME] $*" >&2; exit 1; }

# ---------------------------------------------------------------------
# OS detection (Fedora Silverblue only)
# ---------------------------------------------------------------------
. /etc/os-release || die "Cannot detect OS"
[[ "$ID" == "fedora" || "$ID_LIKE" == *fedora* ]] || die "Fedora only"

# ---------------------------------------------------------------------
# Load git identity (NON-INTERACTIVE)
# ---------------------------------------------------------------------
if [[ ! -f "$GIT_STATE_FILE" ]]; then
  echo "❌ [$MODULE_NAME] Missing git identity state:" >&2
  echo "   $GIT_STATE_FILE" >&2
  echo "👉 Run prereq/setup to collect Git identity" >&2
  exit 2
fi

# shellcheck disable=SC1090
source "$GIT_STATE_FILE"

# Validate required fields (defensive)
: "${GIT_NAME:?Missing GIT_NAME}"
: "${GIT_EMAIL:?Missing GIT_EMAIL}"
: "${GIT_EDITOR:?Missing GIT_EDITOR}"

# Defaults (in case older state exists)
GIT_BRANCH="${GIT_BRANCH:-main}"
GIT_REBASE="${GIT_REBASE:-true}"

# ---------------------------------------------------------------------
# Apply git configuration
# ---------------------------------------------------------------------
log "Applying git configuration"

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch "$GIT_BRANCH"
git config --global core.editor "$GIT_EDITOR"
git config --global pull.rebase "$GIT_REBASE"
git config --global color.ui auto
git config --global core.autocrlf input

# Fedora-native credential storage
if command -v git-credential-libsecret >/dev/null 2>&1; then
  git config --global credential.helper libsecret
  log "Using libsecret credential helper"
else
  git config --global credential.helper 'cache --timeout=3600'
  log "Using in-memory credential cache"
fi

# Aliases
git config --global alias.st status
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.cm "commit -m"
git config --global alias.hist "log --oneline --graph --decorate"

# ---------------------------------------------------------------------
# Zsh integration
# ---------------------------------------------------------------------
install_git_completion_zsh() {
  if [[ ! -f "$FALLBACK_COMPLETION" ]]; then
    mkdir -p "$PLUGIN_DIR"
    curl -fsSL \
      https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.zsh \
      -o "$FALLBACK_COMPLETION"
  fi
}

config_git_shell() {
  [[ -f "$TEMPLATE_FILE" ]] || return 0
  mkdir -p "$ZSH_CONFIG_DIR"
  cp "$TEMPLATE_FILE" "$ZSH_TARGET_FILE"
}

install_git_completion_zsh
config_git_shell

log "✅ Git configured for $GIT_NAME <$GIT_EMAIL>"
exit 0
