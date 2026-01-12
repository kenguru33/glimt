#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE] Failed at line $LINENO" >&2' ERR

MODULE="silverblue-basics"

log() {
  echo "🔧 [$MODULE] $*"
}

# ------------------------------------------------------------
# Guards
# ------------------------------------------------------------
command -v rpm-ostree >/dev/null || {
  echo "❌ rpm-ostree not found (not Silverblue)"
  exit 1
}

command -v jq >/dev/null || {
  echo "❌ jq required to run this script"
  exit 1
}

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(eval echo "~$REAL_USER")"
SYSTEMD_USER_DIR="$REAL_HOME/.config/systemd/user"

# ------------------------------------------------------------
# Wait for rpm-ostree to be ready
# ------------------------------------------------------------
wait_for_rpm_ostree() {
  local timeout=600
  local interval=2
  local elapsed=0

  log "Waiting for rpm-ostree to become ready"

  while true; do
    if rpm-ostree status --json 2>/dev/null | jq -e '
      (.transaction != null) or
      (.deployments[].staged // false)
    ' >/dev/null; then
      if ((elapsed >= timeout)); then
        echo "❌ rpm-ostree still busy after ${timeout}s" >&2
        exit 1
      fi

      sleep "$interval"
      elapsed=$((elapsed + interval))
    else
      break
    fi
  done
}

# ------------------------------------------------------------
# rpm-ostree packages
# ------------------------------------------------------------
RPM_PACKAGES=(
  curl
  jq
  zsh
  wl-clipboard
  git-credential-libsecret
)

REBOOT_REQUIRED=false

wait_for_rpm_ostree

missing_pkgs=()
for pkg in "${RPM_PACKAGES[@]}"; do
  rpm -q "$pkg" &>/dev/null || missing_pkgs+=("$pkg")
done

if ((${#missing_pkgs[@]} > 0)); then
  log "Layering packages: ${missing_pkgs[*]}"
  sudo rpm-ostree install "${missing_pkgs[@]}"
  REBOOT_REQUIRED=true
else
  log "rpm-ostree packages already installed"
fi

# ------------------------------------------------------------
# 1Password (system install)
# ------------------------------------------------------------
wait_for_rpm_ostree

if ! rpm -q 1password &>/dev/null; then
  log "Installing 1Password"

  sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc

  sudo tee /etc/yum.repos.d/1password.repo >/dev/null <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://downloads.1password.com/linux/keys/1password.asc
EOF

  sudo rpm-ostree install 1password
  REBOOT_REQUIRED=true
else
  log "1Password already installed"
fi

# ------------------------------------------------------------
# Homebrew (user-space)
# ------------------------------------------------------------
if ! sudo -u "$REAL_USER" command -v brew >/dev/null; then
  log "Installing Homebrew for user: $REAL_USER"

  sudo -u "$REAL_USER" env NONINTERACTIVE=1 \
    bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  log "Homebrew already installed"
fi

# ------------------------------------------------------------
# Homebrew shellenv for zsh
# ------------------------------------------------------------
BREW_PREFIX="$REAL_HOME/.linuxbrew"
ZSHRC="$REAL_HOME/.zshrc"

if [[ -d "$BREW_PREFIX" ]] && ! grep -q 'brew shellenv' "$ZSHRC" 2>/dev/null; then
  log "Configuring Homebrew shellenv in .zshrc"
  cat >>"$ZSHRC" <<EOF

# Homebrew
eval "\$($BREW_PREFIX/bin/brew shellenv)"
EOF
else
  log "Homebrew shellenv already configured"
fi

# ------------------------------------------------------------
# One-shot systemd user unit to switch shell to zsh
# ------------------------------------------------------------
log "Installing one-shot zsh shell switcher (user systemd service)"

mkdir -p "$SYSTEMD_USER_DIR"

cat >"$SYSTEMD_USER_DIR/set-zsh-shell.service" <<'EOF'
[Unit]
Description=Set zsh as default shell (one-shot)
After=default.target

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c '
ZSH=/usr/bin/zsh
USER_NAME=$(id -un)
CURRENT=$(getent passwd "$USER_NAME" | cut -d: -f7)

if [[ -x "$ZSH" && "$CURRENT" != "$ZSH" ]]; then
  chsh -s "$ZSH" "$USER_NAME"
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
  echo "⚠️  Reboot required to apply rpm-ostree changes"
  echo "👉 Run: systemctl reboot"
else
  echo "✅ All components already installed and active"
fi
