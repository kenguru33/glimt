#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="git-config"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
GLIMT_CONFIG_DIR="$HOME_DIR/.config/glimt"
CONFIG_FILE="$GLIMT_CONFIG_DIR/user-git-info.config"
PLUGIN_DIR="$HOME_DIR/.zsh/plugins/git"
FALLBACK_COMPLETION="$PLUGIN_DIR/git-completion.zsh"

deps() {
  log "Installing git via Homebrew..."
  brew install git
}

install() {
  verify_binary git --version
}

prompt_git_config() {
  mkdir -p "$GLIMT_CONFIG_DIR"

  # Use plain `read` from /dev/tty rather than `gum input`: gum's text widget
  # mis-renders here (duplicate prompt) under the setup orchestration. read is
  # robust regardless of terminal/stdin state and asks exactly once.
  while true; do
    read -rp "📝 Full name: " name < /dev/tty
    [[ -n "$name" ]] && break
    printf '  Name cannot be empty\n' >&2
  done

  while true; do
    read -rp "📧 Email: " email < /dev/tty
    [[ "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]] && break
    printf '  Invalid email\n' >&2
  done

  read -rp "🖊  Default editor [nvim]: " editor < /dev/tty
  editor="${editor:-nvim}"
  read -rp "🌿 Default branch [main]: " branch < /dev/tty
  branch="${branch:-main}"

  local ans
  read -rp "🔁 Use rebase on pull? [y/N]: " ans < /dev/tty
  local rebase=false
  [[ "$ans" =~ ^[Yy]$ ]] && rebase=true

  printf '\nReview Git config:\n  Name:   %s\n  Email:  %s\n  Editor: %s\n  Branch: %s\n  Rebase: %s\n\n' \
    "$name" "$email" "$editor" "$branch" "$rebase"

  read -rp "Save configuration? [Y/n]: " ans < /dev/tty
  [[ "$ans" =~ ^[Nn]$ ]] && die "Aborted"

  cat >"$CONFIG_FILE" <<EOF
name="$name"
email="$email"
editor="$editor"
branch="$branch"
rebase="$rebase"
EOF
}

load_git_config() {
  if [[ "$ACTION" == "reconfigure" || ! -f "$CONFIG_FILE" ]]; then
    prompt_git_config
  fi
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
}

configure_git() {
  log "Applying git configuration..."

  run_as_user git config --global user.name "$name"
  run_as_user git config --global user.email "$email"
  run_as_user git config --global core.editor "$editor"
  run_as_user git config --global init.defaultBranch "$branch"
  run_as_user git config --global pull.rebase "$rebase"
  run_as_user git config --global fetch.prune true
  run_as_user git config --global diff.colorMoved zebra
  run_as_user git config --global rerere.enabled true
  run_as_user git config --global color.ui auto
  run_as_user git config --global core.autocrlf input

  # macOS built-in keychain credential helper
  run_as_user git config --global credential.helper osxkeychain

  run_as_user git config --global alias.st status
  run_as_user git config --global alias.co checkout
  run_as_user git config --global alias.br branch
  run_as_user git config --global alias.cm "commit -m"
  run_as_user git config --global alias.hist "log --oneline --graph --decorate"

  log "Git configured for $name <$email>"
}

install_git_completion_zsh() {
  if [[ ! -f "$FALLBACK_COMPLETION" ]]; then
    mkdir -p "$PLUGIN_DIR"
    curl -fsSL \
      https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.zsh \
      -o "$FALLBACK_COMPLETION"
  fi
}

config_git_shell() {
  mkdir -p "$ZSH_CONFIG_DIR"
  deploy_config "$SCRIPT_DIR/config/git.zsh" "$ZSH_CONFIG_DIR/git.zsh"
}

clean() {
  run_as_user git config --global --unset user.name       || true
  run_as_user git config --global --unset user.email      || true
  run_as_user git config --global --unset core.editor     || true
  run_as_user git config --global --unset init.defaultBranch || true
  run_as_user git config --global --unset pull.rebase     || true
  run_as_user git config --global --unset fetch.prune     || true
  run_as_user git config --global --unset diff.colorMoved || true
  run_as_user git config --global --unset rerere.enabled  || true
  run_as_user git config --global --unset color.ui        || true
  run_as_user git config --global --unset core.autocrlf   || true
  run_as_user git config --global --unset credential.helper || true
  run_as_user git config --global --remove-section alias  || true
  rm -f "$ZSH_CONFIG_DIR/git.zsh"
  rm -rf "$PLUGIN_DIR"
  rm -f "$CONFIG_FILE"
}

case "$ACTION" in
  all)          deps; install; load_git_config; configure_git; install_git_completion_zsh; config_git_shell ;;
  deps)         deps ;;
  install)      install ;;
  config)       load_git_config; configure_git; install_git_completion_zsh; config_git_shell ;;
  reconfigure)  ACTION=reconfigure; load_git_config; configure_git; install_git_completion_zsh; config_git_shell ;;
  clean)        clean ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|reconfigure|clean]"
    exit 1
    ;;
esac
