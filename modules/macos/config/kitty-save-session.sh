#!/usr/bin/env zsh
# Save the current kitty session into the session list under
# ~/.local/share/kitty/sessions/<name>.kitty-session, then notify. Bound to
# ctrl+shift+s in kitty.conf via `launch --type=overlay --cwd=current`, so $PWD
# here is the active pane's directory and the overlay has a TTY to prompt on.
#
# The name is prompted, pre-filled with the active pane's folder name. The
# saved file shows up in kitty's `goto_session <dir>` picker (ctrl+shift+o).
#
# Runs in a transient overlay window (which has a TTY), letting `kitty @` reach
# kitty over that TTY via `allow_remote_control yes` — no control socket needed
# (a backgrounded helper gets neither TTY nor KITTY_LISTEN_ON, so it can't).
# Uses the built-in save_as_session action (full fidelity: tabs, windows,
# running programs, cwds, layout) and writes an ABSOLUTE path so it doesn't
# depend on save_as_session's own cwd resolution.
#
# This overlay window MUST be excluded from the save (--match "not id:..."),
# otherwise its foreground process (this script) is recorded and re-runs on
# restore — an endless save-loop. Abort if we can't identify our own window.
#
# Note: running apps are only captured for panes started with the default shell
# (a bare `launch`, see default.session), which is what enables shell
# integration — save_as_session writes them as kitty-unserialize-data blobs.
set -euo pipefail

notify() { osascript -e "display notification \"$2\" with title \"kitty\" subtitle \"$1\"" >/dev/null 2>&1 || true; }

SESSIONS_DIR="$HOME/.local/share/kitty/sessions"
mkdir -p "$SESSIONS_DIR"

# Prompt for a name, defaulting to the active pane's folder name.
default="${PWD:t}"
print -n "Session name [${default}]: "
read -r name || exit 0
name="${name:-$default}"
name="${name// /-}"   # spaces -> dashes
name="${name//\//-}"  # no path separators in the filename

if [[ -z "$name" || -z "${KITTY_WINDOW_ID:-}" ]]; then
  notify "$SESSIONS_DIR" "Save aborted (no name or window id)"
  exit 1
fi

target="$SESSIONS_DIR/${name}.kitty-session"

# --save-only: don't open an editor to review. --use-foreground-process: also
# restore programs running in each shell on reload (WARNING: re-run on load).
if kitty @ action "save_as_session --save-only --use-foreground-process --match 'not id:${KITTY_WINDOW_ID}' '${target}'"; then
  notify "$target" "Session '${name}' saved"
else
  notify "$target" "Failed to save session"
  exit 1
fi
