#!/usr/bin/env bash
# Fix Norwegian (Macintosh) keyboard on Linux (GNOME, Silverblue-safe)
#
# Applies ONLY if 'Norwegian (Macintosh)' (no+mac) is selected
# Enables macOS-like Option behavior:
#   ⌥ (left Option) + Shift + 7 -> \
#   ⌥ (left Option) + 7         -> |
#
# User-session only — DO NOT run with sudo
# Safe to re-run

set -Eeuo pipefail

MODULE="norwegian-mac-keyboard"

log() { echo "[$MODULE] $*"; }
die() {
  echo "[$MODULE] ERROR: $*" >&2
  exit 1
}

# --------------------------------------------------
# Guard: must NOT be run as root (Silverblue rule)
# --------------------------------------------------
if [[ "$EUID" -eq 0 ]]; then
  die "Do NOT run this script with sudo on Silverblue"
fi

# --------------------------------------------------
# Guard: GNOME session required
# --------------------------------------------------
command -v gsettings >/dev/null || die "GNOME (gsettings) not available"

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
  die "No GNOME session detected (DBUS_SESSION_BUS_ADDRESS missing)"
fi

log "Running as user: $USER"

# --------------------------------------------------
# Check if Norwegian (Macintosh) layout is active
# --------------------------------------------------
if ! gsettings get org.gnome.desktop.input-sources sources |
  grep -q "('xkb', 'no+mac')"; then
  log "Norwegian (Macintosh) keyboard NOT selected — skipping"
  log "Nothing was changed."
  exit 0
fi

log "Norwegian (Macintosh) keyboard detected"

# --------------------------------------------------
# Apply fix: bind LEFT Alt (Option) to Level-3
# --------------------------------------------------
CURRENT_OPTIONS="$(gsettings get org.gnome.desktop.input-sources xkb-options)"

if echo "$CURRENT_OPTIONS" | grep -q "lv3:lalt_switch"; then
  log "Level-3 already bound to left Option — nothing to do"
else
  log "Binding left Option (Alt_L) to Level-3 (macOS behavior)"
  gsettings set org.gnome.desktop.input-sources xkb-options "['lv3:lalt_switch']"
fi

# --------------------------------------------------
# Verification output
# --------------------------------------------------
log "Final keyboard configuration:"
gsettings get org.gnome.desktop.input-sources sources
gsettings get org.gnome.desktop.input-sources xkb-options

cat <<EOF

✅ Norwegian Mac keyboard fix applied.

IMPORTANT:
➡ You MUST log out and log back in for this to fully apply.

After login, these will work exactly like macOS:
  ⌥ (left Option) + Shift + 7  ->  \\
  ⌥ (left Option) + 7         ->  |

Rollback (if ever needed):
  gsettings reset org.gnome.desktop.input-sources xkb-options

EOF
