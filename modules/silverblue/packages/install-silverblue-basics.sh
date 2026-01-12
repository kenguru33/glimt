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

REAL_HOME="$(eval echo "~${SUDO_USER:-$USER}")"

# ------------------------------------------------------------
# Wait for rpm-ostree (ONLY transaction matters)
# ------------------------------------------------------------
wait_for_rpm_ostree() {
  log "Waiting for rpm-ostree to be idle"
  while rpm-ostree status --json | jq -e '.transaction != null' >/dev/null; do
    sleep 2
  done
}

wait_for_rpm_ostree

# ------------------------------------------------------------
# 1Password repository
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
fi

# ------------------------------------------------------------
# rpm-ostree packages
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
sudo rpm-ostree install --idempotent --allow-inactive "${RPM_PACKAGES[@]}"

# ------------------------------------------------------------
# Homebrew (Linux-supported prefix, Silverblue real path)
# ------------------------------------------------------------
BREW_ROOT="/var/home/linuxbrew"
BREW_PREFIX="$BREW_ROOT/.linuxbrew"

log "Preparing Homebrew prefix at $BREW_PREFIX"
sudo mkdir -p "$BREW_PREFIX"
sudo chown -R "$(stat -c '%U' "$REAL_HOME")":"$(stat -c '%G' "$REAL_HOME")" "$BREW_ROOT"

if ! sudo -u "$(stat -c '%U' "$REAL_HOME")" env HOME="$REAL_HOME" command -v brew >/dev/null; then
  log "Installing Homebrew"
  sudo -u "$(stat -c '%U' "$REAL_HOME")" env \
    HOME="$REAL_HOME" \
    NONINTERACTIVE=1 \
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# ------------------------------------------------------------
# Homebrew shellenv (.zshrc)
# ------------------------------------------------------------
ZSHRC="$REAL_HOME/.zshrc"

if ! grep -q 'brew shellenv' "$ZSHRC" 2>/dev/null; then
  log "Configuring Homebrew in .zshrc"
  cat >>"$ZSHRC" <<'EOF'

# Homebrew (Silverblue)
if [[ -x /var/home/linuxbrew/.linuxbrew/bin/brew ]]; then
  eval "$(/var/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
EOF
fi

# ------------------------------------------------------------
# Phase 2: dynamic post-boot oneshot
# ------------------------------------------------------------
POSTBOOT_UNIT="/etc/systemd/system/silverblue-postboot.service"

if [[ ! -f "$POSTBOOT_UNIT" ]]; then
  log "Installing post-boot oneshot to set zsh shell (dynamic user)"

  sudo tee "$POSTBOOT_UNIT" >/dev/null <<'EOF'
[Unit]
Description=Silverblue post-boot setup (set zsh shell)
After=multi-user.target
ConditionPathExists=/usr/bin/zsh

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c '
USER="$(getent passwd | awk -F: '\''$3 >= 1000 { print $1; exit }'\'')"
CURRENT="$(getent passwd "$USER" | cut -d: -f7)"

if [[ "$CURRENT" != "/usr/bin/zsh" ]]; then
  usermod --shell /usr/bin/zsh "$USER"
fi

systemctl disable silverblue-postboot.service
rm -f /etc/systemd/system/silverblue-postboot.service
'

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable silverblue-postboot.service
fi

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo
echo "✅ Phase 1 complete"
echo "👉 Reboot required"
echo "👉 zsh will be set automatically for the primary user"
echo
echo "Run:"
echo "  systemctl reboot"
