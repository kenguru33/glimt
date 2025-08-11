#!/usr/bin/env bash
set -euo pipefail
trap 'echo "❌ ${BASH_SOURCE[0]} failed at: $BASH_COMMAND" >&2' ERR

# --- Config ---
SCRIPT_NAME="bootstrap.sh"
REPO_URL="https://github.com/kenguru33/glimt.git"
REPO_DIR="$HOME/.glimt"
BRANCH="main"
VERBOSE=0

# --- Ensure we have a real TTY (important for bash <(wget ...)) ---
[[ -t 0 ]] || { [[ -e /dev/tty ]] && exec < /dev/tty; }
[[ -t 1 ]] || { [[ -e /dev/tty ]] && exec > /dev/tty; }
[[ -t 2 ]] || { [[ -e /dev/tty ]] && exec 2> /dev/tty; }

# --- Lock OUTSIDE the repo (so we don't pre-create REPO_DIR) ---
LOCK_DIR="$HOME/.cache/glimt"
mkdir -p "$LOCK_DIR"
LOCK="$LOCK_DIR/bootstrap.lock"
exec 9>"$LOCK"
flock -n 9 || { echo "⚠️  Another bootstrap is running. Exiting."; exit 1; }

# --- Args ---
for arg in "$@"; do
  case "$arg" in
    -v|--verbose) VERBOSE=1 ;;
    branch=*)     BRANCH="${arg#branch=}" ;;
    *)
      echo "Usage: $SCRIPT_NAME [--verbose|-v] [branch=<branchname>]"
      exit 2
      ;;
  esac
done

# --- Helper: run quietly but keep stderr visible ---
run() { if [[ "$VERBOSE" -eq 1 ]]; then "$@"; else "$@" 1>/dev/null; fi; }

# --- OS guard ---
[[ -f /etc/os-release ]] || { echo "❌ Could not detect OS." >&2; exit 1; }
. /etc/os-release

# --- Don’t run as root ---
if [[ "$(id -u)" -eq 0 ]]; then
  echo "❌ Do not run as root. Use a normal user." >&2
  exit 1
fi

# --- Sudo upfront ---
echo "🔐 Checking sudo..."
sudo -v || { echo "❌ Sudo unavailable or authentication failed." >&2; exit 1; }

# --- Ensure git ---
if ! command -v git >/dev/null 2>&1; then
  echo "📦 Installing git..."
  if command -v apt-get >/dev/null 2>&1; then
    run sudo apt-get update -y -o Acquire::Retries=3
    run sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq git
  else
    echo "❌ 'git' is required and apt-get is not available." >&2
    exit 1
  fi
fi

# --- Clone or update repo (do NOT pre-create REPO_DIR) ---
echo "📥 Preparing repo at $REPO_DIR (branch: $BRANCH)..."
if [[ -d "$REPO_DIR/.git" ]]; then
  echo "🔄 Updating existing repo..."
  run git -C "$REPO_DIR" fetch origin
  run git -C "$REPO_DIR" checkout "$BRANCH"
  run git -C "$REPO_DIR" reset --hard "origin/$BRANCH"
elif [[ -e "$REPO_DIR" ]]; then
  # Exists but not a git repo (or leftover files) — back it up safely
  TS="$(date +%s)"
  echo "📦 Found non-git directory at $REPO_DIR — moving to ${REPO_DIR}.bak.$TS"
  mv "$REPO_DIR" "${REPO_DIR}.bak.$TS"
  run git clone --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
else
  run git clone --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi

# --- Run installer under systemd-inhibit (prevent sleep) ---
cd "$REPO_DIR"
[[ -f setup.sh ]] || { echo "❌ setup.sh not found in $REPO_DIR" >&2; ls -la; exit 1; }

echo "🚀 Launching installer (sleep inhibited)..."
if command -v systemd-inhibit >/dev/null 2>&1; then
  exec systemd-inhibit --what=handle-lid-switch:sleep:shutdown \
    --why="Glimt setup in progress" \
    bash ./setup.sh ${VERBOSE:+--verbose}
else
  exec bash ./setup.sh ${VERBOSE:+--verbose}
fi
