#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ silverblue-basics failed at line $LINENO" >&2' ERR

MODULE="silverblue-basics"
log() { echo "🔧 [$MODULE] $*"; }

# ------------------------------------------------------------
# Resolve script + modules directory
# ------------------------------------------------------------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
MODULES_DIR="$SCRIPT_DIR/modules"

# ------------------------------------------------------------
# Paths / state
# ------------------------------------------------------------
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(eval echo "~$REAL_USER")"

STATE_DIR="$REAL_HOME/.config/glimt"
mkdir -p "$STATE_DIR"

GIT_STATE_FILE="$STATE_DIR/git.state"

# ------------------------------------------------------------
# Guards
# ------------------------------------------------------------
command -v rpm-ostree >/dev/null || {
  echo "❌ This script is intended for Fedora Silverblue / Atomic"
  exit 1
}

command -v jq >/dev/null || {
  echo "❌ jq is required (install once with rpm-ostree install jq)"
  exit 1
}

# ------------------------------------------------------------
# Sudo warm-up + keepalive (ONE TIME)
# ------------------------------------------------------------
log "Requesting administrator access (one-time)"
sudo -v

(
  while true; do
    sleep 60
    sudo -n true || exit
  done
) &
SUDO_KEEPALIVE_PID=$!

trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

# ------------------------------------------------------------
# STEP 0 — Git identity (ONCE)
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
wait_for_rpm_ostree() {
  log "Waiting for rpm-ostree to be idle"
  while rpm-ostree status --json | jq -e '.transaction != null' >/dev/null; do
    sleep 2
  done
}

reboot_required() {
  rpm-ostree status --json | jq -e '.deployments | length > 1' >/dev/null
}

have_all_rpms() {
  local wanted=("$@")
  local installed
  installed="$(rpm-ostree status --json | jq -r '.deployments[0].packages[]')"

  for pkg in "${wanted[@]}"; do
    grep -qx "$pkg" <<<"$installed" || return 1
  done
  return 0
}

wait_for_rpm_ostree

# ------------------------------------------------------------
# Base RPM packages
# ------------------------------------------------------------
RPM_PACKAGES=(
  zsh
  fish
  git-credential-libsecret
  gnome-shell-extension-blur-my-shell
  gnome-shell-extension-gsconnect
  gnome-shell-extension-appindicator

  # Build tools for Homebrew
  gcc
  gcc-c++
  make
  pkg-config
  glibc-devel

  # Common build deps
  openssl-devel
  libffi-devel
  zlib-devel
)

if have_all_rpms "${RPM_PACKAGES[@]}"; then
  log "Base RPM packages already installed"
else
  log "Installing base RPM packages"
  sudo rpm-ostree install --idempotent --allow-inactive "${RPM_PACKAGES[@]}"
fi

# ------------------------------------------------------------
# rpm-ostree automatic updates
# ------------------------------------------------------------
ENABLE_AUTO_UPDATES="${ENABLE_AUTO_UPDATES:-1}"

if [[ "$ENABLE_AUTO_UPDATES" == "1" ]]; then
  if ! systemctl is-enabled rpm-ostreed-automatic.timer >/dev/null 2>&1; then
    log "Enabling rpm-ostree automatic updates"
    wait_for_rpm_ostree
    sudo systemctl enable --now rpm-ostreed-automatic.timer
  else
    log "rpm-ostree automatic updates already enabled"
  fi
fi

# ------------------------------------------------------------
# Homebrew install (USER ONLY)
# ------------------------------------------------------------
BREW_PREFIX="/var/home/linuxbrew/.linuxbrew"
BREW_BIN="$BREW_PREFIX/bin/brew"

if [[ ! -x "$BREW_BIN" ]]; then
  log "Installing Homebrew for $REAL_USER"

  sudo mkdir -p "$BREW_PREFIX"
  sudo chown -R "$REAL_USER:$REAL_USER" /var/home/linuxbrew

  sudo -u "$REAL_USER" env \
    HOME="$REAL_HOME" \
    USER="$REAL_USER" \
    LOGNAME="$REAL_USER" \
    NONINTERACTIVE=1 \
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  log "Homebrew already installed"
fi

# ------------------------------------------------------------
# STEP — Run ALL modules (NO sudo here)
# ------------------------------------------------------------
MANUAL_ACTIONS=0

if [[ -d "$MODULES_DIR" ]]; then
  log "🔁 Running modules in $MODULES_DIR"

  for module in "$MODULES_DIR"/*.sh; do
    [[ -f "$module" ]] || continue
    name="$(basename "$module")"

    log "▶️  Running module: $name"

    set +e
    bash "$module" all
    rc=$?
    set -e

    case "$rc" in
    0)
      log "✔ Module $name completed"
      ;;
    2)
      log "⏸️  Module $name requires manual action"
      MANUAL_ACTIONS=1
      ;;
    *)
      echo "❌ Module $name failed with exit code $rc" >&2
      exit 1
      ;;
    esac
  done
else
  log "ℹ️  No modules directory found at $MODULES_DIR"
fi

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo
echo "✅ Silverblue basics installed:"
echo "   • Base RPM packages"
echo "   • Homebrew"
echo "   • Modules executed"

if ((MANUAL_ACTIONS)); then
  echo "   • ⚠️  Some modules required manual input"
fi

echo "   • rpm-ostree automatic updates: $(
  systemctl is-enabled rpm-ostreed-automatic.timer >/dev/null 2>&1 && echo enabled || echo disabled
)"

if reboot_required; then
  echo
  echo "⚠️  A reboot is required to apply system changes."
  echo "👉 systemctl reboot"
else
  echo
  echo "✅ No reboot required."
fi

exit 0