#!/bin/bash
set -e

# Try to detect the original user (not root)
REAL_USER="${SUDO_USER:-$USER}"

if ! command -v sudo >/dev/null; then
  echo "❌ 'sudo' is not installed."
  echo "➡️  Install it manually as root:"
  echo "    apt update && apt install sudo"
  exit 1
fi

if ! sudo -v >/dev/null 2>&1; then
  echo "🚫 User '$REAL_USER' does not have sudo privileges or authentication failed."
  echo ""
  echo "🛠️  To give this user sudo access:"
  echo "   1. Switch to root:         su -"
  echo "   2. Run this command:       usermod -aG sudo $REAL_USER"
  echo "   3. Log out and log in again (or reboot)"
  echo ""
  echo "📄 Ensure $REAL_USER is listed in /etc/sudoers (directly or via group)."
  exit 1
fi

sudo -n true
# echo "✅ Sudo access confirmed for '$REAL_USER'."

