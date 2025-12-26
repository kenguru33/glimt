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
# OS detection (Fedora only)
# ---------------------------------------------------------------------
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  die "Cannot detect OS"
fi

[[ "$ID" == "fedora" || "$ID_LIKE" == *fedora* ]] || die "Fedora only"

# ---------------------------------------------------------------------
# Dependencies (Fedora-native)
# ---------------------------------------------------------------------
DEPS=(
  git
  curl
  git-credential-libsecret
  gnome-keyring
)

install_dependencies() {
  log "Installing dependencies…"
  sudo dnf makecache -y
  for pkg in "${DEPS[@]}"; do
    if ! rpm -q "$pkg" &>/dev/null; then
      log "Installing $pkg"
      sudo dnf install -y "$pkg"
    fi
  done
}

# ---------------------------------------------------------------------
# GNOME Keyring (needed for libsecret credential helper on Fedora)
# ---------------------------------------------------------------------
enable_gnome_keyring_socket() {
  local uid runtime_dir
  uid="$(id -u "$REAL_USER" 2>/dev/null || echo "")"
  runtime_dir="/run/user/${uid}"

  # Best-effort: only meaningful on systems with systemd user sessions.
  if ! command -v systemctl >/dev/null 2>&1; then
    log "systemctl not available; skipping gnome-keyring socket enable."
    return 0
  fi

  if [[ -z "$uid" || ! -d "$runtime_dir" ]]; then
    log "No user runtime dir ($runtime_dir); cannot enable gnome-keyring socket automatically."
    log "Run: systemctl --user enable --now gnome-keyring-daemon.socket"
    return 0
  fi

  # When running via sudo, systemctl --user often needs XDG_RUNTIME_DIR/DBUS_SESSION_BUS_ADDRESS.
  if sudo -u "$REAL_USER" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
    systemctl --user enable --now gnome-keyring-daemon.socket 2>/dev/null; then
    log "Enabled GNOME Keyring user socket: gnome-keyring-daemon.socket"
  else
    log "Could not enable GNOME Keyring socket automatically (no user session bus?)."
    log "Run (as your user): systemctl --user enable --now gnome-keyring-daemon.socket"
  fi
}

# ---------------------------------------------------------------------
# Prompt user (gum)
# ---------------------------------------------------------------------
prompt_git_config() {
  mkdir -p "$CONFIG_DIR"

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
  source "$CONFIG_FILE"
}

# ---------------------------------------------------------------------
# Apply git configuration
# ---------------------------------------------------------------------
configure_git() {
  log "Applying git configuration"

  sudo -u "$REAL_USER" git config --global user.name "$name"
  sudo -u "$REAL_USER" git config --global user.email "$email"
  sudo -u "$REAL_USER" git config --global init.defaultBranch "$branch"
  sudo -u "$REAL_USER" git config --global core.editor "$editor"
  sudo -u "$REAL_USER" git config --global pull.rebase "$rebase"
  sudo -u "$REAL_USER" git config --global color.ui auto
  sudo -u "$REAL_USER" git config --global core.autocrlf input

  # -----------------------------------------------------------------
  # Credential helper (Fedora-correct logic)
  # -----------------------------------------------------------------
  if command -v git-credential-manager >/dev/null 2>&1; then
    sudo -u "$REAL_USER" git config --global credential.helper manager
    log "Using Git Credential Manager"
  elif command -v git-credential-libsecret >/dev/null 2>&1; then
    enable_gnome_keyring_socket
    sudo -u "$REAL_USER" git config --global credential.helper libsecret
    log "Using git-credential-libsecret (GNOME Keyring)"
  else
    sudo -u "$REAL_USER" git config --global credential.helper 'cache --timeout=3600'
    log "Using in-memory credential cache (1h)"
  fi

  sudo -u "$REAL_USER" git config --global alias.st status
  sudo -u "$REAL_USER" git config --global alias.co checkout
  sudo -u "$REAL_USER" git config --global alias.br branch
  sudo -u "$REAL_USER" git config --global alias.cm "commit -m"
  sudo -u "$REAL_USER" git config --global alias.hist "log --oneline --graph --decorate"

  log "Git configured for $name <$email>"
}

# ---------------------------------------------------------------------
# Zsh integration
# ---------------------------------------------------------------------
install_git_completion_zsh() {
  if [[ ! -f "$FALLBACK_COMPLETION" ]]; then
    mkdir -p "$PLUGIN_DIR"
    curl -fsSL https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.zsh \
      -o "$FALLBACK_COMPLETION"
    chown -R "$REAL_USER:$REAL_USER" "$PLUGIN_DIR"
  fi
}

config_git_shell() {
  mkdir -p "$ZSH_CONFIG_DIR"
  cp "$TEMPLATE_FILE" "$ZSH_TARGET_FILE"
  chown "$REAL_USER:$REAL_USER" "$ZSH_TARGET_FILE"
}

# ---------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------
clean_git_config() {
  log "Cleaning git config"

  sudo -u "$REAL_USER" git config --global --unset user.name || true
  sudo -u "$REAL_USER" git config --global --unset user.email || true
  sudo -u "$REAL_USER" git config --global --unset credential.helper || true
  sudo -u "$REAL_USER" git config --global --remove-section alias || true

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
