#!/usr/bin/env sh
set -eu

ACTION="${1:-all}"

REPO_ROOT="${GLIMT_ROOT:-$HOME/.glimt}"

SRC_GEN="$REPO_ROOT/modules/debian/config/50-wayland-apps"
SRC_ENVD="$REPO_ROOT/modules/debian/config/10-electron.conf"

DEST_GEN_DIR="$HOME/.config/systemd/user-environment-generators"
DEST_GEN="$DEST_GEN_DIR/50-wayland-apps"

DEST_ENVD_DIR="$HOME/.config/environment.d"
DEST_ENVD="$DEST_ENVD_DIR/10-electron.conf"

deps() {
    :
}

install() {
    mkdir -p "$DEST_GEN_DIR" "$DEST_ENVD_DIR"
    cp "$SRC_GEN" "$DEST_GEN"
    chmod 755 "$DEST_GEN"
    if [ -f "$SRC_ENVD" ]; then
        cp "$SRC_ENVD" "$DEST_ENVD"
        chmod 644 "$DEST_ENVD"
    fi
}

config() {
    :
}

clean() {
    rm -f "$DEST_GEN" "$DEST_ENVD" 2>/dev/null || true
}

case "$ACTION" in
    deps) deps ;;
    install) install ;;
    config) config ;;
    clean) clean ;;
    all) deps; install; config ;;
    *) exit 2 ;;
esac
