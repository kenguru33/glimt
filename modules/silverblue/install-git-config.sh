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
HOME_DIR="${HOME:-$(eval echo "~$REAL_USER")}"

CONFIG_DIR="$HOME_DIR/.config/glimt"
CONFIG_FILE="$CONFIG_DIR/user-git-info.config"

ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSH_TARGET_FILE="$ZSH_CONFIG_DIR/git.zsh"
PLUGIN_DIR="$HOME_DIR/.zsh/plugins/git"
FALLBACK_COMPLETION="$PLUGIN_DIR/git-completion.zsh"
TEMPLATE_FILE="$SCRIPT_DIR/config/git.zsh"

log() { echo "🔧 [$MODULE_NAME] $*"; }
die() {
  echo "❌ [$MODULE_NAME] $*" >&2
  exit 1
}

# ---------------------------------------------------------------------
# OS detection (Fedora Silverblue only)
# ---------------------------------------------------------------------
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  die "Cannot detect OS"
fi

[[ "$ID" == "fedora" || "$ID_LIKE" == *fedora* ]] || die "Fedora only"

# ---------------------------------------------------------------------
# Dependencies (no check - packages should be installed via prereq)
# ---------------------------------------------------------------------
install_dependencies() {
  log "✅ Dependencies should be installed via prereq module"
}

# ---------------------------------------------------------------------
# GNOME Keyring (best-effort)
# ---------------------------------------------------------------------
enable_gnome_keyring_socket() {
  local uid runtime_dir
  uid="$(id -u "$REAL_USER" 2>/dev/null || true)"
  runtime_dir="/run/user/${uid}"

  if ! command -v systemctl >/dev/null 2>&1; then
    return 0
  fi

  if [[ -z "$uid" || ! -d "$runtime_dir" ]]; then
    return 0
  fi

  XDG_RUNTIME_DIR="$runtime_dir" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
    systemctl --user enable --now gnome-keyring-daemon.socket \
    &>/dev/null || true
}

# ---------------------------------------------------------------------
# Prompt user (gum or fallback)
# ---------------------------------------------------------------------
prompt_git_config() {
  mkdir -p "$CONFIG_DIR"

  if command -v gum &>/dev/null; then
    while true; do
      name=$(gum input --prompt "📝 Full name: ")
      [[ -n "$name" ]] && break
      gum style --foreground 1 "Name cannot be empty"
    done

    while true; do
      email=$(gum input --prompt "📧 Email: ")
      [[ "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]] && break
      gum style --foreground 1 "Invalid email"
    done

    editor=$(gum input --prompt "🖊 Default editor:" --value "nvim")
    branch=$(gum input --prompt "🌿 Default branch:" --value "main")

    rebase=false
    gum confirm "🔁 Use rebase on pull?" && rebase=true

    gum format <<EOF
# Review Git config

Name: $name
Email: $email
Editor: $editor
Branch: $branch
Pull rebase: $rebase
EOF

    gum confirm "Save configuration?" || die "Aborted"
  else
    # Fallback to basic prompts
    while true; do
      read -rp "📝 Full name: " name
      [[ -n "$name" ]] && break
      echo "Name cannot be empty"
    done

    while true; do
      read -rp "📧 Email: " email
      [[ "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]] && break
      echo "Invalid email"
    done

    read -rp "🖊 Default editor [nvim]: " editor
    editor="${editor:-nvim}"

    read -rp "🌿 Default branch [main]: " branch
    branch="${branch:-main}"

    read -rp "🔁 Use rebase on pull? [y/N]: " rebase_confirm
    rebase=false
    [[ "$rebase_confirm" =~ ^[Yy]$ ]] && rebase=true
  fi

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

# ---------------------------------------------------------------------
# Apply git configuration
# ---------------------------------------------------------------------
configure_git() {
  log "Applying git configuration"

  git config --global user.name "$name"
  git config --global user.email "$email"
  git config --global init.defaultBranch "$branch"
  git config --global core.editor "$editor"
  git config --global pull.rebase "$rebase"
  git config --global color.ui auto
  git config --global core.autocrlf input

  # Fedora-native credential storage
  if command -v git-credential-libsecret >/dev/null 2>&1; then
    enable_gnome_keyring_socket
    git config --global credential.helper libsecret
    log "Using Fedora-native credential helper (libsecret + GNOME Keyring)"
  else
    git config --global credential.helper 'cache --timeout=3600'
    log "libsecret missing — using in-memory cache (1h)"
  fi

  git config --global alias.st status
  git config --global alias.co checkout
  git config --global alias.br branch
  git config --global alias.cm "commit -m"
  git config --global alias.hist "log --oneline --graph --decorate"

  log "Git configured for $name <$email>"
}

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
  if [[ -f "$TEMPLATE_FILE" ]]; then
    mkdir -p "$ZSH_CONFIG_DIR"
    cp "$TEMPLATE_FILE" "$ZSH_TARGET_FILE"
  else
    log "⚠️  Template file not found: $TEMPLATE_FILE"
  fi
}

# ---------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------
clean_git_config() {
  log "Cleaning git config"

  git config --global --unset user.name || true
  git config --global --unset user.email || true
  git config --global --unset credential.helper || true
  git config --global --remove-section alias || true

  rm -f "$ZSH_TARGET_FILE"
  rm -rf "$PLUGIN_DIR"
  rm -f "$CONFIG_FILE"
}

# ---------------------------------------------------------------------
# Entry point (Glimt-compatible)
# ---------------------------------------------------------------------
case "$ACTION" in
all)
  install_dependencies
  load_git_config
  configure_git
  install_git_completion_zsh
  config_git_shell
  ;;
deps)
  install_dependencies
  ;;
config)
  load_git_config
  configure_git
  install_git_completion_zsh
  config_git_shell
  ;;
reconfigure)
  ACTION=reconfigure
  load_git_config
  configure_git
  install_git_completion_zsh
  config_git_shell
  ;;
clean)
  clean_git_config
  ;;
*)
  echo "Usage: $0 {all|deps|config|reconfigure|clean}"
  exit 1
  ;;
esac
