#!/usr/bin/env sh
set -eu

ACTION="${1:-all}"
REPO_ROOT="${GLIMT_ROOT:-$HOME/.glimt}"

SRC_ENVD="$REPO_ROOT/modules/debian/config/10-wayland.conf"
DEST_ENVD_DIR="$HOME/.config/environment.d"
DEST_ENVD="$DEST_ENVD_DIR/10-wayland.conf"

deps() { :; }

install() {
    mkdir -p "$DEST_ENVD_DIR"
    cp "$SRC_ENVD" "$DEST_ENVD"
    chmod 644 "$DEST_ENVD"
}

config() {
    # Load into current shell and import into systemd --user session
    if [ -f "$DEST_ENVD" ]; then
        set -a
        . "$DEST_ENVD"
        set +a
        if command -v systemctl >/dev/null 2>&1; then
            systemctl --user import-environment $(cut -d= -f1 "$DEST_ENVD") || true
        fi
    fi
}

clean() {
    rm -f "$DEST_ENVD" 2>/dev/null || true
}

case "$ACTION" in
    deps) deps ;;
    install) install ;;
    config) config ;;
    clean) clean ;;
    all) deps; install; config ;;
    *) exit 2 ;;
esac
