#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

MODULE_NAME="ytmusic"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

macos_guard() {
  [[ "$(uname -s)" == "Darwin" ]] || die "macOS only."
}

deps() { log "No additional dependencies."; }

install() {
  if [[ -e "/Applications/YouTube Music.app" ]]; then
    log "YouTube Music already installed."
    return 0
  fi

  local arch
  arch="$(uname -m)"
  local suffix
  case "$arch" in
    arm64)  suffix="arm64" ;;
    x86_64) suffix="x64" ;;
    *) die "Unsupported architecture: $arch" ;;
  esac

  log "Fetching latest YouTube Music release..."
  local version
  version="$(curl -fsSL https://api.github.com/repos/th-ch/youtube-music/releases/latest \
    | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')"
  [[ -n "$version" ]] || die "Could not determine latest YouTube Music version"

  local url="https://github.com/th-ch/youtube-music/releases/download/v${version}/YouTube-Music-${version}-${suffix}.dmg"
  local tmp_dmg
  tmp_dmg="$(mktemp /tmp/youtube-music-XXXXXX)"

  log "Downloading YouTube Music ${version}..."
  curl -fsSL "$url" -o "$tmp_dmg"

  log "Installing YouTube Music..."
  local mount_dir
  mount_dir="$(mktemp -d /tmp/ytmusic-mount-XXXXXX)"
  hdiutil attach "$tmp_dmg" -nobrowse -mountpoint "$mount_dir" -quiet
  cp -R "$mount_dir/YouTube Music.app" "/Applications/"
  hdiutil detach "$mount_dir" -quiet
  rm -rf "$mount_dir" "$tmp_dmg"

  log "YouTube Music ${version} installed."
}

config() { log "No extra configuration needed."; }

clean() {
  rm -rf "/Applications/YouTube Music.app"
  log "YouTube Music removed."
}

macos_guard

case "$ACTION" in
  all)     deps; install; config ;;
  deps)    deps ;;
  install) install ;;
  config)  config ;;
  clean)   clean ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac
