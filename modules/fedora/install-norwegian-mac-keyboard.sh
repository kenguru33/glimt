#!/usr/bin/env bash
# Fix Norwegian (Macintosh) keyboard on Linux (GNOME)
# Applies ONLY if 'no+mac' is selected
# Enables macOS-like Option behavior:
#   ⌥ (left Option) + Shift + 7 -> \
#   ⌥ + 7                     -> |
#
# Safe to re-run
# Fedora / Debian / Ubuntu compatible

set -Eeuo pipefail

MODULE="norwegian-mac-keyboard"

log() { echo "[$MODULE] $*"; }
warn() { echo "[$MODULE] WARNING: $*" >&2; }
die() {
  echo "[$MODULE] ERROR: $*" >&2
  exit 1
}

# --------------------------------------------------
# Guard: GNOME required
# --------------------------------------------------
command -v gsettings >/dev/null || die "GNOME (gsettings) not detected"

# --------------------------------------------------
# Resolve real user (important when run via sudo)
# --------------------------------------------------
REAL_USER="${SUDO_USER:-$USER}"
REAL_UID="$(id -u "$REAL_USER")"

# Best-effort home lookup (not strictly required, but useful)
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6 || true)"

run_as_user() {
  sudo -u "$REAL_USER" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$REAL_UID/bus" \
    "$@"
}

log "Running for user: $REAL_USER"

# --------------------------------------------------
# Check if Norwegian (Macintosh) is selected
# --------------------------------------------------
is_norwegian_mac_keyboard() {
  run_as_user gsettings get org.gnome.desktop.input-sources sources |
    grep -q "('xkb', 'no+mac')"
}

if ! is_norwegian_mac_keyboard; then
  log "Norwegian (Macintosh) keyboard NOT selected — skipping"
  log "Nothing was changed."
  exit 0
fi

log "Norwegian (Macintosh) keyboard detected"

# --------------------------------------------------
# Apply fix: bind LEFT Alt (Option) to Level-3
# --------------------------------------------------
CURRENT_OPTIONS="$(run_as_user gsettings get org.gnome.desktop.input-sources xkb-options)"

if echo "$CURRENT_OPTIONS" | grep -q "lv3:lalt_switch"; then
  log "Level-3 already bound to left Alt — nothing to do"
else
  log "Binding left Option (Alt_L) to Level-3 (macOS behavior)"
  run_as_user gsettings set org.gnome.desktop.input-sources xkb-options "['lv3:lalt_switch']"
fi

# --------------------------------------------------
# Verification output
# --------------------------------------------------
log "Final keyboard configuration:"
run_as_user gsettings get org.gnome.desktop.input-sources sources
run_as_user gsettings get org.gnome.desktop.input-sources xkb-options

cat <<EOF

✅ Norwegian Mac keyboard fix applied.

IMPORTANT:
➡ You MUST log out and log back in for this to fully apply.

After login, these will work exactly like macOS:
  ⌥ (left Option) + Shift + 7  ->  \\
  ⌥ + 7                      ->  |

Rollback (if ever needed):
  gsettings reset org.gnome.desktop.input-sources xkb-options

EOF
