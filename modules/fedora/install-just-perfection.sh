#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="just-perfection"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

EXT_UUID="just-perfection-desktop@just-perfection"
EXT_SEARCH="just-perfection"

require_gnome() {
  command -v gnome-shell >/dev/null || die "GNOME not detected"
  [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] || die "Run from a GNOME session (not sudo / tty / ssh)"
}

# --------------------------------------------------
# deps
# --------------------------------------------------
install_deps() {
  log "Installing dependencies"
  # gnome-extensions (the CLI) ships with gnome-shell itself
  dnf_ensure curl jq
}

# Print a gsettings string list ("['a', 'b']" or "@as []") without <item>
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
# install
# --------------------------------------------------
install_just_perfection() {
  require_gnome

  if [[ -d "$HOME_DIR/.local/share/gnome-shell/extensions/$EXT_UUID" ]]; then
    log "Just Perfection already installed"
    return
  fi

  log "Installing Just Perfection from extensions.gnome.org"

  local gnome_major tmp_zip meta pk info dl
  gnome_major="$(gnome-shell --version | awk '{print int($3)}')"
  tmp_zip="$(mktemp --suffix=.zip)"

  meta="$(curl -fsSL \
    "https://extensions.gnome.org/extension-query/?search=${EXT_SEARCH}" |
    jq -r --arg u "$EXT_UUID" '.extensions[] | select(.uuid==$u)')"

  [[ -n "$meta" ]] || die "Just Perfection not found on extensions.gnome.org"

  pk="$(jq -r '.pk' <<<"$meta")"

  info="$(curl -fsSL \
    "https://extensions.gnome.org/extension-info/?pk=${pk}&shell_version=${gnome_major}")"

  dl="$(jq -r '.download_url' <<<"$info")"
  [[ "$dl" != "null" ]] || die "No compatible Just Perfection version for GNOME $gnome_major"

  curl -fsSL "https://extensions.gnome.org${dl}" -o "$tmp_zip"
  run_as_user gnome-extensions install --force "$tmp_zip"
  rm -f "$tmp_zip"

  if [[ -d "$HOME_DIR/.local/share/gnome-shell/extensions/$EXT_UUID" ]]; then
    log "Just Perfection installed"
  else
    warn "Just Perfection installed but extension directory not found — install may have failed"
  fi
}

# --------------------------------------------------
# config
# --------------------------------------------------
config_just_perfection() {
  require_gnome

  log "Enabling Just Perfection"

  if [[ -d "$HOME_DIR/.local/share/gnome-shell/extensions/$EXT_UUID" ]]; then
    local current
    current="$(run_as_user gsettings get org.gnome.shell enabled-extensions)"
    if [[ "$current" == *"$EXT_UUID"* ]]; then
      log "Just Perfection already enabled"
    elif [[ "$current" == "[]" || "$current" == "@as []" ]]; then
      run_as_user gsettings set org.gnome.shell enabled-extensions "['$EXT_UUID']"
      log "Just Perfection enabled"
    else
      run_as_user gsettings set org.gnome.shell enabled-extensions "${current%]}, '$EXT_UUID']"
      log "Just Perfection enabled"
    fi
  else
    warn "Extension not found — run 'install' first"
  fi
}

# --------------------------------------------------
# clean
# --------------------------------------------------
clean_just_perfection() {
  log "Removing Just Perfection"
  run_as_user gnome-extensions disable "$EXT_UUID" 2>/dev/null || true
  run_as_user gnome-extensions uninstall "$EXT_UUID" 2>/dev/null || true

  # config added the UUID to enabled-extensions — take it out again
  if command -v gsettings >/dev/null 2>&1; then
    local current
    current="$(run_as_user gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true)"
    if [[ "$current" == *"'$EXT_UUID'"* ]]; then
      run_as_user gsettings set org.gnome.shell enabled-extensions \
        "$(gsettings_list_without "$current" "$EXT_UUID")" || true
      log "Removed $EXT_UUID from enabled-extensions"
    fi
  fi
  log "Just Perfection removed"
}

# --------------------------------------------------
# entrypoint
# --------------------------------------------------
case "$ACTION" in
  all)     install_deps; install_just_perfection; config_just_perfection ;;
  deps)    install_deps ;;
  install) install_just_perfection ;;
  config)  config_just_perfection ;;
  clean)   clean_just_perfection ;;
  *)       echo "Usage: $0 {all|deps|install|config|clean}"; exit 1 ;;
esac
