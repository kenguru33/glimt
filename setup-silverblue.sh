#!/usr/bin/env bash
# Fedora Silverblue setup orchestrator
#
# Exit codes:
#   0 = success
#   2 = controlled stop (reboot required)
#   1 = real failure

set -Eeuo pipefail

ERR_TRAP='echo "❌ setup-silverblue.sh failed at: $BASH_COMMAND (line $LINENO)" >&2'
trap "$ERR_TRAP" ERR

# --------------------------------------------------
# Resolve script location (repo root OR modules dir)
# --------------------------------------------------
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

if [[ -x "$SCRIPT_DIR/packages/install-silverblue-prereq.sh" ]]; then
  SILVERBLUE_DIR="$SCRIPT_DIR"
elif [[ -x "$SCRIPT_DIR/modules/silverblue/packages/install-silverblue-prereq.sh" ]]; then
  SILVERBLUE_DIR="$SCRIPT_DIR/modules/silverblue"
else
  echo "❌ Cannot locate Silverblue modules directory."
  exit 1
fi

PREREQ_SCRIPT="$SILVERBLUE_DIR/packages/install-silverblue-prereq.sh"
BOOTSTRAP_FLAG="$HOME/.config/glans/bootstrap.done"

# --------------------------------------------------
# OS guard
# --------------------------------------------------
. /etc/os-release
[[ "$ID" == "fedora" || "$ID_LIKE" == *fedora* ]] || {
  echo "❌ Fedora Silverblue required"
  exit 1
}

# --------------------------------------------------
# GLOBAL SUDO HANDLING (ONE PROMPT)
# --------------------------------------------------
SUDO_KEEPALIVE_PID=""

enable_sudo_once() {
  [[ -t 0 ]] || return 0
  command -v sudo >/dev/null || return 0

  echo
  echo "🔐 Administrator access required (once)."
  echo

  sudo -v || exit 1

  (
    while true; do
      sudo -v
      sleep 30
    done
  ) >/dev/null 2>&1 &

  SUDO_KEEPALIVE_PID=$!
  disown "$SUDO_KEEPALIVE_PID"

  trap 'sudo -k; kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
}

# --------------------------------------------------
# Step 0: Bootstrap (sudo valid here)
# --------------------------------------------------
enable_sudo_once

if [[ ! -f "$BOOTSTRAP_FLAG" ]]; then
  echo "🔧 First-run bootstrap phase"

  bash "$SILVERBLUE_DIR/install-gravatar.sh" bootstrap

  mkdir -p "$(dirname "$BOOTSTRAP_FLAG")"
  touch "$BOOTSTRAP_FLAG"

  echo "✅ Bootstrap complete"
fi

# --------------------------------------------------
# Step 1: Prerequisites
# --------------------------------------------------
echo
echo "📦 Installing rpm-ostree prerequisites..."
echo

set +e
trap - ERR
bash "$PREREQ_SCRIPT" all
rc=$?
trap "$ERR_TRAP" ERR
set -e

if [[ "$rc" -eq 2 ]]; then
  echo "🔁 Reboot required. Rerun setup after reboot."
  exit 2
elif [[ "$rc" -ne 0 ]]; then
  exit "$rc"
fi

# --------------------------------------------------
# Step 2: Verify packages
# --------------------------------------------------
echo
echo "🔍 Verifying prerequisites..."

STATE_FILE="$HOME/.config/glans/prereq.state"
WANT_1PASSWORD="yes"
[[ -f "$STATE_FILE" ]] && source "$STATE_FILE"

PACKAGES=(curl git file jq zsh wl-clipboard)
[[ "$WANT_1PASSWORD" == "yes" ]] && PACKAGES+=(1password)

for pkg in "${PACKAGES[@]}"; do
  rpm -q "$pkg" &>/dev/null || {
    echo "🔁 Package $pkg not active yet — reboot required"
    exit 2
  }
done

echo "✅ Prerequisites active"

# --------------------------------------------------
# Step 3: Run install modules (steady-state)
# --------------------------------------------------
echo
echo "🚀 Running install modules..."
echo

mapfile -t MODULES < <(
  find "$SILVERBLUE_DIR" -maxdepth 1 -type f -name "install-*.sh" \
    ! -name "install-gravatar.sh" \
    ! -path "*/packages/*" \
    -print | sort
)

for module in "${MODULES[@]}"; do
  name="$(basename "$module")"
  echo "▶️  $name"
  bash "$module" all
done

echo
echo "✅ Setup complete"
exit 0
