[[ -o interactive ]] || return

# Refresh the cached Homebrew outdated-count in the background (read and
# rendered by the fastfetch "Updates" module). `brew update` is network-bound,
# so it runs detached and at most every 6h — fastfetch only ever reads the
# cache, so shell startup never blocks on the network.
if command -v brew >/dev/null; then
  () {
    local cache_file="${XDG_CACHE_HOME:-$HOME/.cache}/glimt/brew-outdated-count"
    if [[ ! -f "$cache_file" ]] || [[ -n "$(find "$cache_file" -mmin +360 2>/dev/null)" ]]; then
      (
        mkdir -p "${cache_file:h}"
        brew update --quiet >/dev/null 2>&1
        brew outdated --quiet 2>/dev/null | grep -c . >"$cache_file"
      ) &!
    fi
  }
fi

command -v fastfetch >/dev/null && fastfetch
