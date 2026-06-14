[[ -o interactive ]] || return

# Refresh the cached Homebrew outdated-count in the background (read and
# rendered by the fastfetch "Updates" module). The whole block runs detached,
# so shell startup never blocks. Two cadences keep the count accurate without
# hitting the network every time:
#   - `brew update` (network-bound version-DB refresh) is throttled to every 6h.
#   - `brew outdated` (a fast local check) reruns on every startup, so the count
#     tracks `brew upgrade` and self-corrects on the next prompt instead of
#     lingering stale for up to 6h.
if command -v brew >/dev/null; then
  () {
    local cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/glimt/brew-outdated-count"
    local stamp_file="${cache_file:h}/brew-update-stamp"
    (
      mkdir -p "${cache_file:h}"
      if [[ ! -f "$stamp_file" ]] || [[ -n "$(find "$stamp_file" -mmin +360 2>/dev/null)" ]]; then
        brew update --quiet >/dev/null 2>&1
        touch "$stamp_file"
      fi
      brew outdated --quiet 2>/dev/null | grep -c . >"$cache_file"
    ) &!
  }
fi

command -v fastfetch >/dev/null && fastfetch
