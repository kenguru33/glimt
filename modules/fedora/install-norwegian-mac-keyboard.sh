#!/usr/bin/env bash
# Glimt module: norwegian-mac-keyboard
# Fix the Norwegian (Macintosh) keyboard layout on GNOME (Fedora).
# Applies ONLY if 'no+mac' is selected. Enables macOS-like Option behavior:
#   ⌥ (left Option) + Shift + 7 -> \
#   ⌥ + 7                     -> |
# Actions: all | deps | install | config | clean   (safe to re-run)

set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="norwegian-mac-keyboard"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

SCHEMA="org.gnome.desktop.input-sources"
XKB_OPTION="lv3:lalt_switch"

# --------------------------------------------------
# Helpers
# --------------------------------------------------

# gsettings needs the user's session bus — also when this runs under sudo
run_as_user_dbus() {
  sudo -u "$REAL_USER" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u "$REAL_USER")/bus" \
    "$@"
}

# Exit cleanly (setup continues) when there is no GNOME to configure
require_gsettings() {
  if ! command -v gsettings >/dev/null 2>&1; then
    warn "GNOME (gsettings) not detected — skipping"
    exit 0
  fi
}

is_norwegian_mac_keyboard() {
  run_as_user_dbus gsettings get "$SCHEMA" sources | grep -q "('xkb', 'no+mac')"
}

# Print a gsettings string list ("['a', 'b']" or "@as []") with <item> appended
gsettings_list_with() {
  local list="$1" item="$2"
  if [[ "$list" == "[]" || "$list" == "@as []" || -z "$list" ]]; then
    printf "['%s']" "$item"
  else
    printf "%s, '%s']" "${list%]}" "$item"
  fi
}

# Print a gsettings string list without <item>
gsettings_list_without() {
  local list="$1" item="$2" out="" e
  local -a items=()
  list="${list#@as }"; list="${list#[}"; list="${list%]}"
  IFS=',' read -ra items <<<"$list"
  for e in "${items[@]}"; do
    e="${e#"${e%%[![:space:]]*}"}"; e="${e%"${e##*[![:space:]]}"}"
    [[ -z "$e" || "$e" == "'$item'" ]] && continue
    out+="${out:+, }$e"
  done
  printf '[%s]' "$out"
}

# --------------------------------------------------
# deps / install
# --------------------------------------------------
deps() {
  log "No dependencies (uses gsettings from GNOME)"
}

install() {
  log "Nothing to install — the fix is applied in config"
}

# --------------------------------------------------
# config — bind LEFT Alt (Option) to Level-3
# --------------------------------------------------
config() {
  require_gsettings
  log "Running for user: $REAL_USER"

  if ! is_norwegian_mac_keyboard; then
    log "Norwegian (Macintosh) keyboard NOT selected — skipping"
    log "Nothing was changed."
    return 0
  fi

  log "Norwegian (Macintosh) keyboard detected"

  local current
  current="$(run_as_user_dbus gsettings get "$SCHEMA" xkb-options)"

  if [[ "$current" == *"'$XKB_OPTION'"* ]]; then
    log "Level-3 already bound to left Alt — nothing to do"
  else
    log "Binding left Option (Alt_L) to Level-3 (macOS behavior)"
    # append — keep any xkb-options the user already has
    run_as_user_dbus gsettings set "$SCHEMA" xkb-options "$(gsettings_list_with "$current" "$XKB_OPTION")"
  fi

  log "Final keyboard configuration:"
  run_as_user_dbus gsettings get "$SCHEMA" sources
  run_as_user_dbus gsettings get "$SCHEMA" xkb-options

  cat <<EOF

Norwegian Mac keyboard fix applied.

IMPORTANT:
You MUST log out and log back in for this to fully apply.

After login, these will work exactly like macOS:
  ⌥ (left Option) + Shift + 7  ->  \\
  ⌥ + 7                      ->  |

Rollback: $0 clean

EOF
}

# --------------------------------------------------
# clean — remove only the option config added
# --------------------------------------------------
clean() {
  require_gsettings

  local current
  current="$(run_as_user_dbus gsettings get "$SCHEMA" xkb-options 2>/dev/null || true)"

  if [[ "$current" == *"'$XKB_OPTION'"* ]]; then
    run_as_user_dbus gsettings set "$SCHEMA" xkb-options "$(gsettings_list_without "$current" "$XKB_OPTION")"
    log "Removed $XKB_OPTION from xkb-options (log out and back in to apply)"
  else
    log "$XKB_OPTION not set — nothing to clean"
  fi
}

# --------------------------------------------------
# entrypoint
# --------------------------------------------------
case "$ACTION" in
all)
  deps
  install
  config
  ;;
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
*)
  die "Unknown action: $ACTION (use: all | deps | install | config | clean)"
  ;;
esac
