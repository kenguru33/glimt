#!/usr/bin/env bash
# Glimt – Fedora Silverblue setup orchestrator (FINAL)
#
# Exit codes:
#   0 = success
#   2 = controlled stop (reboot or manual action required)
#   1 = real failure

set -Eeuo pipefail

ERR_TRAP='echo "❌ setup-silverblue.sh failed at: $BASH_COMMAND (line $LINENO)" >&2'
trap "$ERR_TRAP" ERR

# --------------------------------------------------
# Resolve script location
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

# --------------------------------------------------
# State tracking
# --------------------------------------------------
STATE_DIR="$HOME/.config/glimt/setup"
mkdir -p "$STATE_DIR"

BOOTSTRAP_FLAG="$STATE_DIR/bootstrap.done"
STEP1_DONE="$STATE_DIR/step1-prereq.done"
STEP2_DONE="$STATE_DIR/step2-verified.done"
AUTORESUME_FLAG="$STATE_DIR/autoresume.enabled"

# --------------------------------------------------
# OS guard
# --------------------------------------------------
. /etc/os-release
[[ "$ID" == "fedora" || "$ID_LIKE" == *fedora* ]] || {
  echo "❌ Fedora Silverblue required"
  exit 1
}

# --------------------------------------------------
# Sudo handling (once)
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
# Auto-resume banner
# --------------------------------------------------
if [[ -f "$AUTORESUME_FLAG" ]]; then
  echo "🔄 Resuming Glimt setup after reboot..."
fi

# --------------------------------------------------
# Step 0: Bootstrap (once)
# --------------------------------------------------
if [[ ! -f "$BOOTSTRAP_FLAG" ]]; then
  enable_sudo_once

  echo "🔧 Step 0: First-run bootstrap"
  bash "$SILVERBLUE_DIR/install-gravatar.sh" bootstrap

  touch "$BOOTSTRAP_FLAG"
  echo "✅ Bootstrap complete"
fi

# --------------------------------------------------
# Ask-and-reboot helper
# --------------------------------------------------
ask_and_reboot() {
  echo
  read -rp "🔁 Reboot now to continue setup? [Y/n]: " reply
  case "$reply" in
    n|N|no|NO)
      echo "ℹ️  Reboot later and rerun setup manually."
      exit 2
      ;;
    *)
      echo "🔧 Setup will automatically resume after reboot."

      USER_SYSTEMD_DIR="$HOME/.config/systemd/user"
      mkdir -p "$USER_SYSTEMD_DIR"

      cat >"$USER_SYSTEMD_DIR/glimt-setup-resume.service" <<'EOF'
[Unit]
Description=Resume Glimt Silverblue setup after reboot
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=%h/glimt/setup-silverblue.sh
ExecStartPost=/usr/bin/systemctl --user disable glimt-setup-resume.service
ExecStartPost=/usr/bin/rm -f %h/.config/glimt/setup/autoresume.enabled

[Install]
WantedBy=default.target
EOF

      systemctl --user daemon-reload
      systemctl --user enable glimt-setup-resume.service

      touch "$AUTORESUME_FLAG"
      systemctl reboot
      ;;
  esac
}

# --------------------------------------------------
# Step 1: rpm-ostree prerequisites
# --------------------------------------------------
if [[ ! -f "$STEP1_DONE" ]]; then
  echo
  echo "📦 Step 1: Installing rpm-ostree prerequisites..."
  echo

  set +e
  trap - ERR
  bash "$PREREQ_SCRIPT" all
  rc=$?
  trap "$ERR_TRAP" ERR
  set -e

  case "$rc" in
    0)
      # Nothing staged → continue
      touch "$STEP1_DONE"
      ;;
    2)
      # Packages staged → reboot required
      touch "$STEP1_DONE"
      ask_and_reboot
      ;;
    *)
      exit "$rc"
      ;;
  esac
fi

# --------------------------------------------------
# Step 2: Verify prerequisites
# --------------------------------------------------
if [[ ! -f "$STEP2_DONE" ]]; then
  echo
  echo "🔍 Step 2: Verifying prerequisites..."
  echo

  STATE_FILE="$HOME/.config/glimt/prereq.state"
  WANT_1PASSWORD="yes"
  [[ -f "$STATE_FILE" ]] && source "$STATE_FILE"

  PACKAGES=(curl git file jq zsh wl-clipboard)
  [[ "$WANT_1PASSWORD" == "yes" ]] && PACKAGES+=(1password)

  for pkg in "${PACKAGES[@]}"; do
    if ! rpm -q "$pkg" &>/dev/null; then
      echo "🔁 Package '$pkg' not active yet — reboot required"
      exit 2
    fi
  done

  touch "$STEP2_DONE"
  echo "✅ Prerequisites verified"
fi

# --------------------------------------------------
# Step 3: Run install modules
# --------------------------------------------------
echo
echo "🚀 Step 3: Running install modules..."
echo

mapfile -t MODULES < <(
  find "$SILVERBLUE_DIR" -maxdepth 1 -type f -name "install-*.sh" \
    ! -name "install-gravatar.sh" \
    ! -path "*/packages/*" \
    -print | sort
)

for module in "${MODULES[@]}"; do
  name="$(basename "$module")"
  echo "▶️  Running: $name"
  bash "$module" all
done

# --------------------------------------------------
# Done
# --------------------------------------------------
rm -f "$AUTORESUME_FLAG"

echo
echo "✅ Glimt setup complete!"
echo "ℹ️  Logout or reboot may be required for some changes."
exit 0
