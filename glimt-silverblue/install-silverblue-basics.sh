#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ silverblue-basics failed at line $LINENO" >&2' ERR

MODULE="silverblue-basics"
log() { echo "🔧 [$MODULE] $*"; }

# ------------------------------------------------------------
# Paths
# ------------------------------------------------------------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# ------------------------------------------------------------
# User / state
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
  echo "❌ Fedora Silverblue / Atomic only"
  exit 1
}

command -v jq >/dev/null || {
  echo "❌ jq is required (rpm-ostree install jq)"
  exit 1
}

# ------------------------------------------------------------
# Sudo keepalive (ONE TIME)
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
# Git identity (ONCE)
# ------------------------------------------------------------
if [[ ! -f "$GIT_STATE_FILE" ]]; then
  [[ -t 0 ]] || exit 2

  read -rp "👉 Git full name: " GIT_NAME
  read -rp "👉 Git email: " GIT_EMAIL
  read -rp "👉 Git editor [nvim]: " GIT_EDITOR
  GIT_EDITOR="${GIT_EDITOR:-nvim}"

  cat >"$GIT_STATE_FILE" <<EOF
GIT_NAME="$GIT_NAME"
GIT_EMAIL="$GIT_EMAIL"
GIT_EDITOR="$GIT_EDITOR"
GIT_BRANCH="main"
GIT_REBASE="true"
EOF
fi

# ------------------------------------------------------------
# Helpers (ROBUST)
# ------------------------------------------------------------
wait_for_rpm_ostree() {
  while rpm-ostree status --json | jq -e '.transaction != null' >/dev/null; do
    sleep 2
  done
}

reboot_required() {
  rpm-ostree status --json | jq -e '.deployments | length > 1' >/dev/null
}

pkg_present() {
  rpm-ostree status --json |
    jq -e --arg pkg "$1" '.. | strings | select(. == $pkg)' >/dev/null
}

have_rpmfusion() {
  rpm-ostree status --json |
    jq -e '.. | strings | select(test("rpmfusion-(free|nonfree)-release"))' >/dev/null
}

wait_for_rpm_ostree

# ------------------------------------------------------------
# RPM Fusion
# ------------------------------------------------------------
if have_rpmfusion; then
  log "RPM Fusion already present (active or pending)"
else
  log "Installing RPM Fusion repositories"
  sudo rpm-ostree install \
    https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
fi

# ------------------------------------------------------------
# 1Password
# ------------------------------------------------------------
if pkg_present 1password; then
  log "1Password already present"
else
  log "Installing 1Password"
  sudo tee /etc/yum.repos.d/1password.repo >/dev/null <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF
  sudo rpm-ostree install 1password 1password-cli
fi

# ------------------------------------------------------------
# Media codecs (FILTERED, SAFE)
# ------------------------------------------------------------
if have_rpmfusion; then
  log "Installing media codecs (RPM Fusion)"

  CODECS=(
    gstreamer1-plugin-libav
    gstreamer1-plugins-bad-free-extras
    gstreamer1-plugins-bad-freeworld
    gstreamer1-plugins-ugly
    gstreamer1-vaapi
  )

  TO_INSTALL=()
  for pkg in "${CODECS[@]}"; do
    if ! pkg_present "$pkg"; then
      TO_INSTALL+=("$pkg")
    fi
  done

  if ((${#TO_INSTALL[@]})); then
    sudo rpm-ostree install --allow-inactive "${TO_INSTALL[@]}"
  else
    log "All media codecs already requested"
  fi

  if pkg_present ffmpeg-free; then
    log "Replacing ffmpeg-free with full ffmpeg"
    sudo rpm-ostree override remove \
      ffmpeg-free \
      libavcodec-free \
      libavdevice-free \
      libavfilter-free \
      libavformat-free \
      libavutil-free \
      libpostproc-free \
      libswresample-free \
      libswscale-free \
      fdk-aac-free \
      --install ffmpeg
  else
    log "Full ffmpeg already present"
  fi
fi

# ------------------------------------------------------------
# Homebrew
# ------------------------------------------------------------
BREW_PREFIX="/var/home/linuxbrew/.linuxbrew"
if [[ ! -x "$BREW_PREFIX/bin/brew" ]]; then
  log "Installing Homebrew"
  sudo mkdir -p "$BREW_PREFIX"
  sudo chown -R "$REAL_USER:$REAL_USER" /var/home/linuxbrew
  sudo -u "$REAL_USER" NONINTERACTIVE=1 bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  log "Homebrew already installed"
fi

# ------------------------------------------------------------
# Modules
# ------------------------------------------------------------
if [[ -d "$MODULES_DIR" ]]; then
  log "Running modules"
  for m in "$MODULES_DIR"/*.sh; do
    [[ -f "$m" ]] || continue
    bash "$m" all || true
  done
fi

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo
echo "✅ Silverblue system prepared"
if reboot_required; then
  echo "⚠️  Reboot required → systemctl reboot"
else
  echo "✅ No reboot required"
fi

exit 0
