#!/usr/bin/env bash
# Glimt module: Silverblue prereq
#
# Exit code contract:
#   0 = success
#   2 = reboot required (controlled stop)
#   1 = real failure

set -Eeuo pipefail

MODULE_NAME="prereq"
log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

STATE_DIR="$HOME_DIR/.config/glans"
STATE_FILE="$STATE_DIR/prereq.state"
mkdir -p "$STATE_DIR"

# --------------------------------------------------
# Fedora / Silverblue guard
# --------------------------------------------------
. /etc/os-release
[[ "$ID" == "fedora" || "$ID_LIKE" == *fedora* ]] || {
  log "❌ Fedora Silverblue required"
  exit 1
}

# --------------------------------------------------
# Ask user about 1Password (ONCE, default YES)
# --------------------------------------------------
WANT_1PASSWORD=""

if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE"
fi

if [[ -z "${WANT_1PASSWORD:-}" ]]; then
  if [[ -t 0 ]]; then
    echo ""
    echo "🔐 Optional component: 1Password"
    echo ""
    echo "1Password integrates with:"
    echo "  • system keyring"
    echo "  • SSH agent"
    echo "  • browsers"
    echo ""
    read -rp "👉 Install 1Password system-wide? [Y/n]: " reply
    case "$reply" in
      n|N|no|NO) WANT_1PASSWORD="no" ;;
      *)         WANT_1PASSWORD="yes" ;;
    esac
  else
    WANT_1PASSWORD="yes"
  fi

  echo "WANT_1PASSWORD=$WANT_1PASSWORD" >"$STATE_FILE"
fi

log "🔐 1Password install choice: $WANT_1PASSWORD"

# --------------------------------------------------
# Pending rpm-ostree deployment detection (QUIET)
# --------------------------------------------------
pending_deployment() {
  local json
  set +o pipefail
  json="$(rpm-ostree status --json 2>/dev/null)"
  set -o pipefail

  jq -e '
    .deployments[]
    | select(.booted == true)
    | (
        (.requested-packages | length > 0) or
        (.requested-base-removals | length > 0) or
        (.requested-base-local-replacements | length > 0)
      )
  ' <<<"$json" >/dev/null 2>&1
}

reboot_required_banner() {
  cat <<'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 🔁 REBOOT REQUIRED

 rpm-ostree has staged changes.
 You MUST reboot before rerunning this script.

 👉 Run:
     systemctl reboot
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF
}

if pending_deployment; then
  reboot_required_banner
  exit 2
fi

# --------------------------------------------------
# HARD FAILURE: Homebrew env pollution
# --------------------------------------------------
if systemctl --user show-environment | grep -q "$HOME_DIR/.linuxbrew"; then
  log "❌ systemd user environment polluted with ~/.linuxbrew"
  exit 1
fi

if echo "$PATH" | grep -q "$HOME_DIR/.linuxbrew"; then
  log "❌ PATH polluted with ~/.linuxbrew"
  exit 1
fi

# --------------------------------------------------
# 1Password repo + key (Silverblue-correct)
# --------------------------------------------------
if [[ "$WANT_1PASSWORD" == "yes" ]]; then
  log "🔑 Configuring 1Password yum repository"

  sudo mkdir -p /etc/pki/rpm-gpg

  if [[ ! -f /etc/pki/rpm-gpg/RPM-GPG-KEY-1password ]]; then
    sudo curl -fsSL \
      https://downloads.1password.com/linux/keys/1password.asc \
      -o /etc/pki/rpm-gpg/RPM-GPG-KEY-1password
    sudo chmod 644 /etc/pki/rpm-gpg/RPM-GPG-KEY-1password
    log "✅ 1Password GPG key installed"
  else
    log "ℹ️  1Password GPG key already present"
  fi

  if [[ ! -f /etc/yum.repos.d/1password.repo ]]; then
    sudo tee /etc/yum.repos.d/1password.repo >/dev/null <<'EOF'
[1password]
name=1Password Stable Channel
baseurl=https://downloads.1password.com/linux/rpm/stable/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-1password
EOF
    sudo chmod 644 /etc/yum.repos.d/1password.repo
    log "✅ 1Password repository added"
  else
    log "ℹ️  1Password repository already present"
  fi
fi

# --------------------------------------------------
# rpm-ostree packages
# --------------------------------------------------
PACKAGES=(
  curl
  git
  file
  jq
  zsh
  wl-clipboard
)

[[ "$WANT_1PASSWORD" == "yes" ]] && PACKAGES+=(1password)

# --------------------------------------------------
# Install rpm-ostree packages
# --------------------------------------------------
log "📦 Installing rpm-ostree packages..."
log "    Packages: ${PACKAGES[*]}"

output=""
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

log "✅ Prerequisites complete"
exit 0
