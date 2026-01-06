#!/usr/bin/env bash
# Setup script for Fedora Silverblue
#
# Exit code contract:
#   0 = success
#   2 = reboot required (controlled stop, NOT an error)
#   1 = real failure

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SILVERBLUE_DIR="$SCRIPT_DIR/modules/silverblue"
PREREQ_SCRIPT="$SILVERBLUE_DIR/packages/install-silverblue-prereq.sh"

# --------------------------------------------------
# Generic error trap (real errors only)
# --------------------------------------------------
trap 'echo "❌ setup-silverblue.sh failed at: $BASH_COMMAND (line $LINENO)" >&2' ERR

# --------------------------------------------------
# OS Check
# --------------------------------------------------
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *fedora* ]]; then
  echo "❌ This script is for Fedora Silverblue only."
  echo "   Detected OS: $ID"
  exit 1
fi

# --------------------------------------------------
# Helper: run prereq with clean reboot semantics
# --------------------------------------------------
run_prereq_or_reboot() {
  local prereq="$1"

  echo "📦 Step 1: Installing prerequisites via rpm-ostree..."
  echo ""

  # IMPORTANT:
  # rpm-ostree uses internal pipes.
  # With `set -o pipefail`, this can emit harmless SIGPIPE noise.
  # Therefore we temporarily disable pipefail ONLY for this call.
  set +o pipefail
  trap - ERR
  set +e

  "$prereq" all
  local rc=$?

  set -e
  trap 'echo "❌ setup-silverblue.sh failed at: $BASH_COMMAND (line $LINENO)" >&2' ERR
  set -o pipefail

  case "$rc" in
    0)
      return 0
      ;;
    2)
      # Controlled stop: reboot required
      exit 2
      ;;
    *)
      echo ""
      echo "❌ Prerequisite step failed."
      echo "   Exit code: $rc"
      exit "$rc"
      ;;
  esac
}

# --------------------------------------------------
# Step 1: Prerequisites (HARD STOP ON FAILURE)
# --------------------------------------------------
if [[ ! -x "$PREREQ_SCRIPT" ]]; then
  echo "❌ Prerequisite script not found or not executable:"
  echo "   $PREREQ_SCRIPT"
  exit 1
fi

run_prereq_or_reboot "$PREREQ_SCRIPT"

# --------------------------------------------------
# Step 2: Verify prerequisite packages are active
# --------------------------------------------------
echo ""
echo "🔍 Step 2: Verifying all prerequisite packages are installed..."

PACKAGES_TXT="$SILVERBLUE_DIR/packages/rpm-ostree-packages.txt"
if [[ ! -f "$PACKAGES_TXT" ]]; then
  echo "❌ Packages file not found: $PACKAGES_TXT"
  exit 1
fi

declare -a PACKAGES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// }" ]] && continue
  PACKAGES+=("$line")
done < "$PACKAGES_TXT"

MISSING=()
for pkg in "${PACKAGES[@]}"; do
  rpm -q "$pkg" &>/dev/null || MISSING+=("$pkg")
done

if (( ${#MISSING[@]} > 0 )); then
  echo ""
  echo "🔁 Packages are staged but not active yet."
  echo "   Missing: ${MISSING[*]}"
  echo ""
  echo "👉 Reboot and rerun:"
  echo "   systemctl reboot"
  exit 2
fi

echo "✅ All prerequisite packages are active!"
echo ""

# --------------------------------------------------
# Step 3: Run install modules (STOP ON FIRST FAILURE)
# --------------------------------------------------
echo "🚀 Step 3: Running install modules..."
echo ""

PRIORITY_SCRIPTS=(
  "install-git-config.sh"
  "install-homebrew.sh"
)

mapfile -t ALL_SCRIPTS < <(
  find "$SILVERBLUE_DIR" -maxdepth 1 -type f -name "install-*.sh" \
    -not -path "*/not_used/*" \
    -not -path "*/packages/*" \
    -print 2>/dev/null | sort
)

if (( ${#ALL_SCRIPTS[@]} == 0 )); then
  echo "ℹ️  No install scripts found."
  exit 0
fi

declare -a PRIORITY=()
declare -a REMAINING=()

for script in "${ALL_SCRIPTS[@]}"; do
  name="$(basename "$script")"
  if printf '%s\n' "${PRIORITY_SCRIPTS[@]}" | grep -qx "$name"; then
    PRIORITY+=("$script")
  else
    REMAINING+=("$script")
  fi
done

echo "Found ${#ALL_SCRIPTS[@]} install script(s):"
for script in "${ALL_SCRIPTS[@]}"; do
  name="$(basename "$script")"
  if printf '%s\n' "${PRIORITY_SCRIPTS[@]}" | grep -qx "$name"; then
    echo "  - $name (priority)"
  else
    echo "  - $name"
  fi
done
echo ""

run_module_or_die() {
  local script="$1"
  local name
  name="$(basename "$script")"

  echo "▶️  Running: $name"
  chmod +x "$script"
  bash "$script" all
  echo "✅ Finished: $name"
  echo ""
}

if (( ${#PRIORITY[@]} > 0 )); then
  echo "📌 Running priority modules..."
  for script in "${PRIORITY[@]}"; do
    run_module_or_die "$script"
  done
fi

if (( ${#REMAINING[@]} > 0 )); then
  echo "📦 Running remaining modules..."
  for script in "${REMAINING[@]}"; do
    run_module_or_die "$script"
  done
fi

# --------------------------------------------------
# Done
# --------------------------------------------------
echo "✅ Setup complete!"
echo ""
echo "ℹ️  If rpm-ostree packages were installed earlier, a reboot may still be required."
