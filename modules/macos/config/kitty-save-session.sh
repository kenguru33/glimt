#!/usr/bin/env zsh
# Save the current kitty session to ./.kitty.session in the ACTIVE PANE's
# working directory, then notify. Bound to ctrl+shift+s in kitty.conf via
# `launch --type=overlay --cwd=current`, so $PWD here is the active pane's dir.
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

target="$PWD/.kitty.session"

if [[ -z "${KITTY_WINDOW_ID:-}" ]]; then
  notify "$target" "Save aborted (no window id)"
  exit 1
fi

# --save-only: don't open an editor to review. --use-foreground-process: also
# restore programs running in each shell on reload (WARNING: re-run on load).
if kitty @ action "save_as_session --save-only --use-foreground-process --match 'not id:${KITTY_WINDOW_ID}' '${target}'"; then
  notify "$target" "Session saved"
else
  notify "$target" "Failed to save session"
  exit 1
fi
