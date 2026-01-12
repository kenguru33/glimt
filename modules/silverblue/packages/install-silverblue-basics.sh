#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE] Failed at line $LINENO" >&2' ERR

MODULE="silverblue-basics"
log() { echo "🔧 [$MODULE] $*"; }

command -v rpm-ostree >/dev/null || {
  echo "❌ Not Silverblue"
  exit 1
}

command -v jq >/dev/null || {
  echo "❌ jq required"
  exit 1
}

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(eval echo "~$REAL_USER")"
SYSTEMD_USER_DIR="$REAL_HOME/.config/systemd/user"

# ------------------------------------------------------------
# Wait for rpm-ostree (transaction only)
# ------------------------------------------------------------
wait_for_rpm_ostree() {
  while rpm-ostree status --json | jq -e '.transaction != null' >/dev/null; do
    sleep 2
  done
}

wait_for_rpm_ostree

# ------------------------------------------------------------
# Add 1Password repo (NO rpm --import)
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
# rpm-ostree packages (single transaction)
# ------------------------------------------------------------
RPM_PACKAGES=(
  curl
  jq
  zsh
  wl-clipboard
  git-credential-libsecret
  1password
)

missing=()
for pkg in "${RPM_PACKAGES[@]}"; do
  rpm -q "$pkg" &>/dev/null || missing+=("$pkg")
done

REBOOT_REQUIRED=false

if ((${#missing[@]} > 0)); then
  wait_for_rpm_ostree
  log "Installing packages: ${missing[*]}"
  sudo rpm-ostree install "${missing[@]}"
  REBOOT_REQUIRED=true
else
  log "All rpm-ostree packages already installed"
fi

# ------------------------------------------------------------
# Homebrew (user space)
# ------------------------------------------------------------
if ! sudo -u "$REAL_USER" command -v brew >/dev/null; then
  log "Installing Homebrew"
  sudo -u "$REAL_USER" env NONINTERACTIVE=1 \
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# ------------------------------------------------------------
# Homebrew shellenv
# ------------------------------------------------------------
BREW_PREFIX="$REAL_HOME/.linuxbrew"
ZSHRC="$REAL_HOME/.zshrc"

if [[ -d "$BREW_PREFIX" ]] && ! grep -q 'brew shellenv' "$ZSHRC" 2>/dev/null; then
  cat >>"$ZSHRC" <<EOF

# Homebrew
eval "\$($BREW_PREFIX/bin/brew shellenv)"
EOF
fi

# ------------------------------------------------------------
# One-shot zsh shell switch (post reboot)
# ------------------------------------------------------------
mkdir -p "$SYSTEMD_USER_DIR"

cat >"$SYSTEMD_USER_DIR/set-zsh-shell.service" <<'EOF'
[Unit]
Description=Set zsh as default shell (one-shot)

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c '
if [[ -x /usr/bin/zsh ]]; then
  USER=$(id -un)
  CURRENT=$(getent passwd "$USER" | cut -d: -f7)
  [[ "$CURRENT" != "/usr/bin/zsh" ]] && chsh -s /usr/bin/zsh "$USER"
fi
systemctl --user disable set-zsh-shell.service
rm -f ~/.config/systemd/user/set-zsh-shell.service
'

[Install]
WantedBy=default.target
EOF

sudo -u "$REAL_USER" systemctl --user daemon-reexec
sudo -u "$REAL_USER" systemctl --user enable set-zsh-shell.service

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo
if $REBOOT_REQUIRED; then
  echo "⚠️  Reboot required"
  echo "👉 systemctl reboot"
else
  echo "✅ System already configured"
fi
