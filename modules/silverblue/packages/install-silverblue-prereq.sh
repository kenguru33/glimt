#!/usr/bin/env bash
# Glimt module: prereq
# Silverblue-safe, Linuxbrew-correct, reboot-aware, hard-fail
# Actions: all | deps | install | config | clean

set -Eeuo pipefail

MODULE_NAME="prereq"
ACTION="${1:-all}"

log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

# --------------------------------------------------
# Fedora / Silverblue guard
# --------------------------------------------------
. /etc/os-release
if [[ "$ID" != "fedora" && "$ID_LIKE" != *fedora* ]]; then
  printf "[%s] ❌ Fedora-based system required\n" "$MODULE_NAME" >&2
  exit 1
fi

# --------------------------------------------------
# Detect pending rpm-ostree deployment
# --------------------------------------------------
pending_deployment() {
  rpm-ostree status --json \
    | jq -e '.deployments | map(select(.booted == false)) | length > 0' \
    >/dev/null 2>&1
}

reboot_required_banner() {
  cat <<'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 🔁 REBOOT REQUIRED

 rpm-ostree has a pending deployment.
 You MUST reboot before rerunning this script.

 👉 Run:
     systemctl reboot
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

# --------------------------------------------------
# BLOCK reruns if reboot is pending
# --------------------------------------------------
if pending_deployment; then
  reboot_required_banner
  exit 2
fi

# --------------------------------------------------
# Homebrew prefix (canonical Linuxbrew)
# --------------------------------------------------
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
BREW_BIN="$BREW_PREFIX/bin/brew"

log "🍺 Homebrew prefix resolved to: $BREW_PREFIX"

# --------------------------------------------------
# HARD FAILURE: refuse inconsistent Homebrew state
# --------------------------------------------------
hard_fail_if_brew_inconsistent() {
  if systemctl --user show-environment | grep -q "$HOME_DIR/.linuxbrew"; then
    printf "[%s] ❌ systemd user environment contains forbidden Homebrew prefix: %s\n" \
      "$MODULE_NAME" "$HOME_DIR/.linuxbrew" >&2
    exit 1
  fi

  if echo "$PATH" | grep -q "$HOME_DIR/.linuxbrew"; then
    printf "[%s] ❌ PATH contains forbidden Homebrew prefix: %s\n" \
      "$MODULE_NAME" "$HOME_DIR/.linuxbrew" >&2
    exit 1
  fi

  if [[ -f "$BREW_BIN" && ! -x "$BREW_BIN" ]]; then
    printf "[%s] ❌ brew exists but is not executable: %s\n" \
      "$MODULE_NAME" "$BREW_BIN" >&2
    exit 1
  fi

  if [[ -x "$BREW_BIN" ]] && ! "$BREW_BIN" --version >/dev/null 2>&1; then
    printf "[%s] ❌ brew detected but not runnable: %s\n" \
      "$MODULE_NAME" "$BREW_BIN" >&2
    exit 1
  fi
}

hard_fail_if_brew_inconsistent

# --------------------------------------------------
# rpm-ostree prerequisite packages
# --------------------------------------------------
PACKAGES=(
  curl
  git
  file
  jq
  zsh
  wl-clipboard
)

# --------------------------------------------------
deps() {
  log "📦 No additional deps required"
}

# --------------------------------------------------
install_packages() {
  log "📦 Installing prerequisite packages via rpm-ostree…"

  local output
  if ! output=$(sudo rpm-ostree install -y --allow-inactive "${PACKAGES[@]}" 2>&1); then
    if echo "$output" | grep -qi "already requested"; then
      log "ℹ️  Packages already requested in pending deployment"
    elif echo "$output" | grep -qi "already provided"; then
      log "ℹ️  Packages already provided by base image"
    else
      echo "$output" >&2
      exit 1
    fi
  fi

  if pending_deployment; then
    reboot_required_banner
    exit 2
  fi
}

# --------------------------------------------------
install_homebrew() {
  if [[ -x "$BREW_BIN" ]]; then
    log "✅ Homebrew already installed"
    return
  fi

  log "🍺 Installing Homebrew (Linuxbrew canonical prefix)"

  sudo mkdir -p /home/linuxbrew
  sudo chown "$REAL_USER:$REAL_USER" /home/linuxbrew

  NONINTERACTIVE=1 \
    sudo -u "$REAL_USER" /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ ! -x "$BREW_BIN" ]]; then
    printf "[%s] ❌ Homebrew installation failed\n" "$MODULE_NAME" >&2
    exit 1
  fi

  log "✅ Homebrew installed successfully"
}

# --------------------------------------------------
clean_old_homebrew_config() {
  log "🧹 Removing stale Homebrew config"

  sed -i '/linuxbrew/d' \
    "$HOME_DIR/.bashrc" \
    "$HOME_DIR/.bash_profile" \
    "$HOME_DIR/.profile" 2>/dev/null || true

  rm -rf "$HOME_DIR/.linuxbrew"
}

# --------------------------------------------------
config_bash() {
  log "🛠 Configuring bash for Homebrew"

  clean_old_homebrew_config

  local bashrc="$HOME_DIR/.bashrc"
  local bash_profile="$HOME_DIR/.bash_profile"

  touch "$bashrc"
  chown "$REAL_USER:$REAL_USER" "$bashrc"

  if [[ ! -f "$bash_profile" ]]; then
    cat >"$bash_profile" <<'EOF'
[[ -f ~/.bashrc ]] && source ~/.bashrc
EOF
    chown "$REAL_USER:$REAL_USER" "$bash_profile"
  fi

  sed -i '/# Homebrew (Linuxbrew)/,/^fi$/d' "$bashrc" || true

  cat >>"$bashrc" <<EOF

# Homebrew (Linuxbrew)
if [[ -x "$BREW_BIN" ]]; then
  eval "\$($BREW_BIN shellenv)"
fi
EOF

  chown "$REAL_USER:$REAL_USER" "$bashrc"

  log "✅ Bash configured for Homebrew"
}

# --------------------------------------------------
config() {
  config_bash
  log "ℹ️  Log out + log in (or reboot) to activate PATH changes"
}

# --------------------------------------------------
clean() {
  log "🧹 Removing Homebrew and configuration"

  rm -rf "$BREW_PREFIX"
  clean_old_homebrew_config

  log "ℹ️  rpm-ostree removals require reboot"
}

# --------------------------------------------------
install() {
  install_packages
  install_homebrew
  config
}

# --------------------------------------------------
case "$ACTION" in
  deps) deps ;;
  install) install ;;
  config) config ;;
  clean) clean ;;
  all)
    deps
    install
    ;;
  *)
    echo "Usage: $0 {all|deps|install|config|clean}"
    exit 1
    ;;
esac
