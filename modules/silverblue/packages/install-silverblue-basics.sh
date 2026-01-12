#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE] Failed at line $LINENO" >&2' ERR

MODULE="silverblue-basics"
log() { echo "🔧 [$MODULE] $*"; }

# ------------------------------------------------------------
# Guards
# ------------------------------------------------------------
command -v rpm-ostree >/dev/null || {
  echo "❌ Not running on Fedora Silverblue"
  exit 1
}

command -v jq >/dev/null || {
  echo "❌ jq is required"
  exit 1
}

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(eval echo "~$REAL_USER")"

# ------------------------------------------------------------
# Wait for rpm-ostree (ONLY transaction matters)
# ------------------------------------------------------------
wait_for_rpm_ostree() {
  log "Waiting for rpm-ostree to be idle"
  while rpm-ostree status --json | jq -e '.transaction != null' >/dev/null; do
    sleep 2
  done
}

# ------------------------------------------------------------
# Phase 1: system setup (safe before reboot)
# ------------------------------------------------------------
wait_for_rpm_ostree

# ------------------------------------------------------------
# 1Password repository (Silverblue-correct)
# ------------------------------------------------------------
if [[ ! -f /etc/yum.repos.d/1password.repo ]]; then
  log "Adding 1Password repository"
  sudo tee /etc/yum.repos.d/1password.repo >/dev/null <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF
else
  log "1Password repo already present"
fi

# ------------------------------------------------------------
# rpm-ostree packages (idempotent + base-safe)
# ------------------------------------------------------------
RPM_PACKAGES=(
  curl
  jq
  zsh
  wl-clipboard
  git-credential-libsecret
  1password
)

log "Ensuring rpm-ostree packages are requested"
wait_for_rpm_ostree
sudo rpm-ostree install \
  --idempotent \
  --allow-inactive \
  "${RPM_PACKAGES[@]}"

# ------------------------------------------------------------
# Homebrew (Linux-supported prefix ONLY)
# ------------------------------------------------------------
BREW_ROOT="/home/linuxbrew"
BREW_PREFIX="$BREW_ROOT/.linuxbrew"

log "Preparing Homebrew prefix at $BREW_PREFIX"
sudo mkdir -p "$BREW_PREFIX"
sudo chown -R "$REAL_USER:$REAL_USER" "$BREW_ROOT"

if ! sudo -u "$REAL_USER" env HOME="$REAL_HOME" command -v brew >/dev/null; then
  log "Installing Homebrew for $REAL_USER"
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
# Add Homebrew to PATH (zsh)
# ------------------------------------------------------------
ZSHRC="$REAL_HOME/.zshrc"
BREW_SHELLENV='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'

if ! grep -q '/home/linuxbrew/.linuxbrew/bin/brew shellenv' "$ZSHRC" 2>/dev/null; then
  log "Adding Homebrew to PATH in .zshrc"
  cat >>"$ZSHRC" <<EOF

# Homebrew
$BREW_SHELLENV
EOF
fi

# ------------------------------------------------------------
# Phase 2: set zsh as shell (ONLY when it exists)
# ------------------------------------------------------------
if [[ -x /usr/bin/zsh ]]; then
  CURRENT_SHELL="$(getent passwd "$REAL_USER" | cut -d: -f7)"

  if [[ "$CURRENT_SHELL" != "/usr/bin/zsh" ]]; then
    log "Setting zsh as default shell for $REAL_USER (one-time)"
    sudo usermod --shell /usr/bin/zsh "$REAL_USER"
  else
    log "zsh already set as default shell"
  fi
else
  log "zsh not available yet (expected before reboot)"
fi

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo
if [[ ! -x /usr/bin/zsh ]]; then
  echo "⚠️  Reboot required to activate rpm-ostree changes"
  echo "👉 After reboot, run this script ONCE more"
  echo "👉 zsh will then be set automatically"
else
  echo "✅ Setup complete"
  echo "👉 Next login will use zsh"
fi
