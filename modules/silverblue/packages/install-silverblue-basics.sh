#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ silverblue-basics failed at line $LINENO" >&2' ERR

MODULE="silverblue-basics"
log() { echo "🔧 [$MODULE] $*"; }

# ------------------------------------------------------------
# Resolve module root (RELATIVE, NEVER hardcoded)
# ------------------------------------------------------------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
SILVERBLUE_DIR="$(dirname "$SCRIPT_DIR")"
# ~/.glimt/modules/silverblue

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
# STEP 0b — Apply git config (RELATIVE PATH)
# ------------------------------------------------------------
GIT_CONFIG_SCRIPT="$SILVERBLUE_DIR/install-git-config.sh"

if [[ ! -x "$GIT_CONFIG_SCRIPT" ]]; then
  log "❌ Git config script not found:"
  log "   $GIT_CONFIG_SCRIPT"
  exit 1
fi

log "🔧 Applying Git configuration"
bash "$GIT_CONFIG_SCRIPT" all

# ------------------------------------------------------------
# Wait for rpm-ostree to be idle
# ------------------------------------------------------------
wait_for_rpm_ostree() {
  log "Waiting for rpm-ostree to be idle"
  while rpm-ostree status --json | jq -e '.transaction != null' >/dev/null; do
    sleep 2
  done
}

wait_for_rpm_ostree

# ------------------------------------------------------------
# Base RPM packages (image-safe, idempotent)
# ------------------------------------------------------------
RPM_PACKAGES=(
  curl
  jq
  zsh
  wl-clipboard
  git-credential-libsecret
)

log "Ensuring base RPM packages are installed"
wait_for_rpm_ostree
sudo rpm-ostree install \
  --idempotent \
  --allow-inactive \
  "${RPM_PACKAGES[@]}"

# ------------------------------------------------------------
# Homebrew install (user-space)
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
# Helper: append block once
# ------------------------------------------------------------
add_if_missing() {
  local file="$1"
  local marker="$2"
  local content="$3"

  [[ -f "$file" ]] || touch "$file"
  if ! grep -q "$marker" "$file"; then
    log "Configuring $(basename "$file")"
    printf "\n%s\n" "$content" >>"$file"
  fi
}

# ------------------------------------------------------------
# zsh (~/.zshrc)
# ------------------------------------------------------------
ZSHRC="$REAL_HOME/.zshrc"
add_if_missing "$ZSHRC" "linuxbrew/.linuxbrew/bin/brew shellenv" '
# Homebrew
if [[ -x /var/home/linuxbrew/.linuxbrew/bin/brew ]]; then
  eval "$(/var/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Homebrew zsh completions
if [[ -d /var/home/linuxbrew/.linuxbrew/share/zsh/site-functions ]]; then
  fpath+=(/var/home/linuxbrew/.linuxbrew/share/zsh/site-functions)
fi
'

# ------------------------------------------------------------
# bash (~/.bashrc)
# ------------------------------------------------------------
BASHRC="$REAL_HOME/.bashrc"
add_if_missing "$BASHRC" "linuxbrew/.linuxbrew/bin/brew shellenv" '
# Homebrew
if [ -x /var/home/linuxbrew/.linuxbrew/bin/brew ]; then
  eval "$(/var/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
'

# ------------------------------------------------------------
# fish (~/.config/fish/config.fish)
# ------------------------------------------------------------
FISH_CONFIG="$REAL_HOME/.config/fish/config.fish"
mkdir -p "$(dirname "$FISH_CONFIG")"

if ! grep -q "linuxbrew/.linuxbrew/bin/brew shellenv" "$FISH_CONFIG" 2>/dev/null; then
  log "Configuring fish Homebrew integration"
  cat >>"$FISH_CONFIG" <<'EOF'

# Homebrew
if test -x /var/home/linuxbrew/.linuxbrew/bin/brew
  eval (/var/home/linuxbrew/.linuxbrew/bin/brew shellenv)
end

# Homebrew fish completions
if test -d /var/home/linuxbrew/.linuxbrew/share/fish/vendor_completions.d
  set -gx fish_complete_path \
    /var/home/linuxbrew/.linuxbrew/share/fish/vendor_completions.d \
    $fish_complete_path
end
EOF
fi

# ------------------------------------------------------------
# brew doctor guard (non-fatal)
# ------------------------------------------------------------
if sudo -u "$REAL_USER" "$BREW_BIN" doctor >/dev/null 2>&1; then
  log "brew doctor: OK"
else
  echo
  echo "⚠️  brew doctor reported warnings."
  echo "👉 Common on Silverblue, usually safe."
  echo "👉 Inspect manually with:"
  echo "   brew doctor"
fi

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo
echo "✅ Silverblue basics installed:"
echo "   • Base RPM packages"
echo "   • Git configured"
echo "   • Homebrew"
echo "   • Homebrew configured for zsh, bash, fish"
echo
echo "ℹ️  Shell is NOT changed."
echo "   Choose manually if desired:"
echo "     chsh -s /usr/bin/zsh"
echo "     chsh -s /usr/bin/fish"
echo
echo "⚠️  Reboot required to apply rpm-ostree changes."
echo "👉 systemctl reboot"
