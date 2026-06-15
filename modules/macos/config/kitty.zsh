# === kitty session launcher ===
# Wrap `kitty` so that launching it with no arguments restores a session:
#   1. a project-local .kitty.session in the current directory, else
#   2. the global ~/.config/kitty/default.session, else
#   3. a plain kitty window.
# Any explicit arguments (kitty @, kitty +kitten, etc.) bypass the wrapper.
if command -v kitty &>/dev/null; then
  kitty() {
    if [[ $# -gt 0 ]]; then
      command kitty "$@"
    elif [[ -f .kitty.session ]]; then
      # Absolute path: kitty resolves a relative --session against its config
      # dir (~/.config/kitty), not the cwd, so a bare ".kitty.session" fails.
      if [[ -n "${KITTY_WINDOW_ID:-}" ]]; then
        # Already inside kitty: load the session into THIS instance (new OS
        # window, same process) via remote control instead of spawning a
        # second kitty. --single-instance can't join a Dock-launched kitty,
        # so goto_session is the only way to reuse the running instance.
        # Fall back to a fresh instance if remote control is unavailable.
        kitty @ action goto_session "$PWD/.kitty.session" 2>/dev/null \
          || command kitty --session "$PWD/.kitty.session"
      else
        command kitty --session "$PWD/.kitty.session"
      fi
    elif [[ -f ~/.config/kitty/default.session ]]; then
      if [[ -n "${KITTY_WINDOW_ID:-}" ]]; then
        # Already inside kitty: reuse the running instance (see the
        # .kitty.session branch above). goto_session switches to the default
        # session's window if it is already open instead of duplicating it.
        kitty @ action goto_session ~/.config/kitty/default.session 2>/dev/null \
          || command kitty --session ~/.config/kitty/default.session
      else
        command kitty --session ~/.config/kitty/default.session
      fi
    else
      command kitty
    fi
  }
fi
