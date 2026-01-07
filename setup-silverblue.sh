#!/usr/bin/env bash
# Glimt – Fedora Silverblue setup orchestrator (FINAL)
#
# Exit codes:
#   0 = success
#   2 = controlled stop (reboot or manual action required)
#   1 = real failure

set -Eeuo pipefail
trap 'echo "❌ setup-silverblue.sh failed at: $BASH_COMMAND (line $LINENO)" >&2' ERR

# --------------------------------------------------
# Identity reconfigure (explicit)
# --------------------------------------------------
if [[ "${1:-}" == "reconfigure-identity" ]]; then
  echo "♻️  Reconfiguring identity (Git, Gravatar, SSH)"

  rm -f \
    "$HOME/.config/glimt/git.state" \
    "$HOME/.config/glimt/set-user-avatar.config"

  rm -f "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519.pub" 2>/dev/null || true

  echo "✅ Identity reset complete"
  echo "👉 Re-run setup-silverblue.sh"
  exit 0
fi

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
  disown
}

# --------------------------------------------------
# Auto-resume banner
# --------------------------------------------------
[[ -f "$AUTORESUME_FLAG" ]] && echo "🔄 Resuming Glimt setup after reboot..."

# --------------------------------------------------
# Step 0: Bootstrap (NO identity here)
# --------------------------------------------------
if [[ ! -f "$BOOTSTRAP_FLAG" ]]; then
  enable_sudo_once
  echo "🔧 Step 0: Bootstrap"
  touch "$BOOTSTRAP_FLAG"
  echo "✅ Bootstrap complete"
fi

# --------------------------------------------------
# Ask-and-reboot helper
# --------------------------------------------------
ask_and_reboot() {
  read -rp "🔁 Reboot now to continue setup? [Y/n]: " reply
  case "$reply" in
    n|N|no|NO)
      echo "ℹ️  Reboot later and rerun setup."
      exit 2
      ;;
    *)
      echo "🔧 Setup will resume automatically after reboot."
      mkdir -p "$HOME/.config/systemd/user"

      cat >"$HOME/.config/systemd/user/glimt-setup-resume.service" <<'EOF'
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
# Step 1: rpm-ostree prereq
# --------------------------------------------------
if [[ ! -f "$STEP1_DONE" ]]; then
  echo "📦 Step 1: Installing prerequisites..."
  set +e
  bash "$PREREQ_SCRIPT" all
  rc=$?
  set -e

  case "$rc" in
    0) touch "$STEP1_DONE" ;;
    2) touch "$STEP1_DONE"; ask_and_reboot ;;
    *) exit "$rc" ;;
  esac
fi

# --------------------------------------------------
# Step 2: Verify prereq
# --------------------------------------------------
if [[ ! -f "$STEP2_DONE" ]]; then
  echo "🔍 Step 2: Verifying prerequisites..."
  for pkg in curl git file jq zsh wl-clipboard; do
    rpm -q "$pkg" &>/dev/null || exit 2
  done
  touch "$STEP2_DONE"
  echo "✅ Prerequisites verified"
fi

# --------------------------------------------------
# Step 2.5: Gravatar (Git → Gravatar → GNOME)
# --------------------------------------------------
echo "🖼 Step 2.5: Setting user avatar..."
set +e
bash "$SILVERBLUE_DIR/install-gravatar.sh" all
rc=$?
set -e

case "$rc" in
  0) echo "✅ Avatar configured" ;;
  2) echo "⏸️  Avatar requires manual sudo"; exit 2 ;;
  *) exit "$rc" ;;
esac

# --------------------------------------------------
# Step 3: Install modules
# --------------------------------------------------
echo "🚀 Step 3: Running install modules..."

mapfile -t MODULES < <(
  find "$SILVERBLUE_DIR" -maxdepth 1 -type f -name "install-*.sh" \
    ! -name "install-gravatar.sh" \
    ! -path "*/packages/*" \
    -print | sort
)

for module in "${MODULES[@]}"; do
  echo "▶️  Running: $(basename "$module")"
  bash "$module" all
done

rm -f "$AUTORESUME_FLAG"

echo
echo "✅ Glimt setup complete!"
echo "ℹ️  Logout or reboot may be required."
exit 0
