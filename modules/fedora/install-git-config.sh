#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="git-config"
ACTION="${1:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

# ---------------------------------------------------------------------
# Paths / user context
# ---------------------------------------------------------------------
CONFIG_DIR="$HOME_DIR/.config/glimt"
CONFIG_FILE="$CONFIG_DIR/user-git-info.config"

ZSH_CONFIG_DIR="$HOME_DIR/.zsh/config"
ZSH_TARGET_FILE="$ZSH_CONFIG_DIR/git.zsh"
PLUGIN_DIR="$HOME_DIR/.zsh/plugins/git"
FALLBACK_COMPLETION="$PLUGIN_DIR/git-completion.zsh"
TEMPLATE_FILE="$SCRIPT_DIR/config/git.zsh"

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
  libsecret
)

install_dependencies() {
  log "Installing dependencies…"
  dnf_ensure "${DEPS[@]}"
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

  sudo -u "$REAL_USER" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime_dir/bus" \
    systemctl --user enable --now gnome-keyring-daemon.socket \
    &>/dev/null || true
}

# ---------------------------------------------------------------------
# Prompt user (gum)
# ---------------------------------------------------------------------
# setup.sh collects these values up front (before the progress bar hides the
# terminal) and saves them to $CONFIG_FILE; the module only prompts itself on
# `reconfigure` or when run by hand without a saved config.
is_interactive() { [[ -t 0 && -t 1 ]]; }

save_git_config() {
  run_as_user mkdir -p "$CONFIG_DIR"
  run_as_user tee "$CONFIG_FILE" >/dev/null <<EOF
name="$name"
email="$email"
editor="$editor"
branch="$branch"
rebase="$rebase"
EOF
}

prompt_git_config() {
  while true; do
    name=$(gum input --prompt "Full name: ")
    [[ -n "$name" ]] && break
    gum style --foreground 1 "Name cannot be empty"
  done

  while true; do
    email=$(gum input --prompt "Email: ")
    [[ "$email" =~ ^[^@]+@[^@]+\.[^@]+$ ]] && break
    gum style --foreground 1 "Invalid email"
  done

  editor=$(gum input --prompt "Default editor:" --value "nvim")
  branch=$(gum input --prompt "Default branch:" --value "main")

  rebase=false
  gum confirm "Use rebase on pull?" && rebase=true

  gum format <<EOF
# Review Git config

Name: $name
Email: $email
Editor: $editor
Branch: $branch
Pull rebase: $rebase
EOF

  gum confirm "Save configuration?" || die "Aborted"

  save_git_config
}

load_git_config() {
  name="" email="" editor="nvim" branch="main" rebase="false"

  if [[ "$ACTION" != "reconfigure" && -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    return 0
  fi

  if is_interactive && command -v gum >/dev/null 2>&1; then
    prompt_git_config
    return 0
  fi

  [[ "$ACTION" == "reconfigure" ]] && die "reconfigure needs a terminal (and gum)"

  # No terminal and nothing saved: keep whatever identity git already has
  # rather than hanging on a prompt nobody can answer.
  warn "No saved git info ($CONFIG_FILE) and no terminal — not prompting."
  warn "Run '$0 reconfigure' in a terminal to set your git identity."
  name="$(run_as_user git config --global user.name 2>/dev/null || true)"
  email="$(run_as_user git config --global user.email 2>/dev/null || true)"
}

# ---------------------------------------------------------------------
# Apply git configuration (Fedora way)
# ---------------------------------------------------------------------
configure_git() {
  log "Applying git configuration"

  if [[ -n "$name" ]]; then
    run_as_user git config --global user.name "$name"
  fi
  if [[ -n "$email" ]]; then
    run_as_user git config --global user.email "$email"
  fi
  run_as_user git config --global init.defaultBranch "$branch"
  run_as_user git config --global core.editor "$editor"
  run_as_user git config --global pull.rebase "$rebase"
  run_as_user git config --global color.ui auto
  run_as_user git config --global core.autocrlf input

  # Fedora-native credential storage
  if command -v git-credential-libsecret >/dev/null 2>&1; then
    enable_gnome_keyring_socket
    run_as_user git config --global credential.helper libsecret
    log "Using Fedora-native credential helper (libsecret + GNOME Keyring)"
  else
    run_as_user git config --global credential.helper 'cache --timeout=3600'
    log "libsecret missing — using in-memory cache (1h)"
  fi

  run_as_user git config --global alias.st status
  run_as_user git config --global alias.co checkout
  run_as_user git config --global alias.br branch
  run_as_user git config --global alias.cm "commit -m"
  run_as_user git config --global alias.hist "log --oneline --graph --decorate"

  log "Git configured for $name <$email>"
}

# ---------------------------------------------------------------------
# Zsh integration
# ---------------------------------------------------------------------
install_git_completion_zsh() {
  if [[ ! -f "$FALLBACK_COMPLETION" ]]; then
    run_as_user mkdir -p "$PLUGIN_DIR"
    run_as_user curl -fsSL \
      https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.zsh \
      -o "$FALLBACK_COMPLETION"
  fi
}

config_git_shell() {
  deploy_config "$TEMPLATE_FILE" "$ZSH_TARGET_FILE"
}

# ---------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------
clean_git_config() {
  log "Cleaning git config"

  run_as_user git config --global --unset user.name || true
  run_as_user git config --global --unset user.email || true
  run_as_user git config --global --unset credential.helper || true
  for key in init.defaultBranch core.editor pull.rebase color.ui core.autocrlf; do
    run_as_user git config --global --unset "$key" || true
  done
  # Only the aliases glimt sets — keep any aliases the user added themselves
  for a in st co br cm hist; do
    run_as_user git config --global --unset "alias.$a" || true
  done

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
  install_git_completion_zsh
  load_git_config
  configure_git
  config_git_shell
  ;;
deps)
  install_dependencies
  ;;
install)
  install_git_completion_zsh
  ;;
config)
  load_git_config
  configure_git
  install_git_completion_zsh
  config_git_shell
  ;;
reconfigure)
  load_git_config
  configure_git
  install_git_completion_zsh
  config_git_shell
  ;;
clean)
  clean_git_config
  ;;
*)
  echo "Usage: $0 {all|deps|install|config|reconfigure|clean}"
  exit 1
  ;;
esac
