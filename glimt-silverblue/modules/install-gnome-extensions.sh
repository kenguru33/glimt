#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ gnome-extensions module failed at line $LINENO" >&2' ERR

MODULE_NAME="gnome-extensions"
ACTION="${1:-all}"

HOME_DIR="$HOME"
EXT_DIR="$HOME_DIR/.local/share/gnome-shell/extensions"
SCHEMA_DIR="$HOME_DIR/.local/share/glib-2.0/schemas"

GNOME_VERSION="$(gnome-shell --version | awk '{print $3}')"
TMP_ZIP="$(mktemp)"

EXTENSIONS=(
  "blur-my-shell@aunetx"
  "rounded-window-corners@fxgn"
  "tilingshell@ferrarodomenico.com"
)

# --------------------------------------------------
# Guards
# --------------------------------------------------
command -v gnome-extensions >/dev/null || {
  echo "❌ gnome-extensions not available (layer it via rpm-ostree)"
  exit 1
}

command -v jq >/dev/null || {
  echo "❌ jq not available (layer it via rpm-ostree)"
  exit 1
}

command -v curl >/dev/null || {
  echo "❌ curl not available"
  exit 1
}

mkdir -p "$EXT_DIR" "$SCHEMA_DIR"

# --------------------------------------------------
install_extensions() {
  echo "🧩 Installing GNOME extensions (user-local)…"

  for EXT_ID in "${EXTENSIONS[@]}"; do
    echo "🌐 Resolving $EXT_ID"

    METADATA="$(
      curl -fsSL "https://extensions.gnome.org/extension-query/?search=${EXT_ID}" |
        jq -r --arg uuid "$EXT_ID" '.extensions[] | select(.uuid == $uuid)'
    )"

    if [[ -z "$METADATA" ]]; then
      echo "❌ Extension not found: $EXT_ID"
      continue
    fi

    PK_ID="$(jq -r '.pk' <<<"$METADATA")"

    VERSION_JSON="$(
      curl -fsSL "https://extensions.gnome.org/extension-info/?pk=${PK_ID}&shell_version=${GNOME_VERSION}"
    )"

    DL_PATH="$(jq -r '.download_url' <<<"$VERSION_JSON")"
    if [[ "$DL_PATH" == "null" ]]; then
      echo "⚠️ No compatible version for GNOME $GNOME_VERSION ($EXT_ID)"
      continue
    fi

    curl -fsSL "https://extensions.gnome.org${DL_PATH}" -o "$TMP_ZIP"

    TMP_UNPACK="$(mktemp -d)"
    unzip -oq "$TMP_ZIP" -d "$TMP_UNPACK"

    META_FILE="$(find "$TMP_UNPACK" -name metadata.json | head -n1)"
    UUID="$(jq -r '.uuid' "$META_FILE")"

    DEST="$EXT_DIR/$UUID"
    echo "📁 Installing $UUID"

    rm -rf "$DEST"
    mkdir -p "$DEST"
    cp -r "$(dirname "$META_FILE")"/* "$DEST"

    if [[ -d "$DEST/schemas" ]]; then
      echo "🔧 Installing schemas for $UUID"
      cp "$DEST/schemas"/*.xml "$SCHEMA_DIR/" 2>/dev/null || true
    fi
  done

  if [[ -d "$SCHEMA_DIR" ]]; then
    echo "🧠 Compiling user schemas"
    glib-compile-schemas "$SCHEMA_DIR"
  fi

  schedule_enable_extensions
}

# --------------------------------------------------
schedule_enable_extensions() {
  echo "🕒 Scheduling extension enablement on next login"

  mkdir -p "$HOME_DIR/.config/systemd/user"

  cat >"$HOME_DIR/.config/systemd/user/enable-gnome-extensions.service" <<EOF
[Unit]
Description=Enable GNOME Shell extensions after login
After=graphical-session.target

[Service]
Type=oneshot
ExecStart=/usr/bin/gnome-extensions enable blur-my-shell@aunetx
ExecStart=/usr/bin/gnome-extensions enable rounded-window-corners@fxgn
ExecStart=/usr/bin/gnome-extensions enable tilingshell@ferrarodomenico.com
ExecStart=/usr/bin/systemctl --user disable enable-gnome-extensions.service

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable enable-gnome-extensions.service
}

# --------------------------------------------------
config_extensions() {
  echo "⚙️ Configuring extensions…"

  export GSETTINGS_SCHEMA_DIR="$SCHEMA_DIR"

  # ---- Blur My Shell ----
  if gsettings list-schemas | grep -q org.gnome.shell.extensions.blur-my-shell; then
    echo "🎨 Blur My Shell"
    gsettings set org.gnome.shell.extensions.blur-my-shell brightness 0.8
    gsettings set org.gnome.shell.extensions.blur-my-shell sigma 30
    gsettings set org.gnome.shell.extensions.blur-my-shell color-and-noise true
    gsettings set org.gnome.shell.extensions.blur-my-shell hacks-level 1

    command -v dconf >/dev/null &&
      dconf write /org/gnome/shell/extensions/blur-my-shell/panel/override-background-dynamically false || true
  else
    echo "⏳ Blur My Shell schema not available yet (login required)"
  fi

  # ---- Tiling Shell ----
  if gsettings list-schemas | grep -q org.gnome.shell.extensions.tilingshell; then
    echo "🪟 Tiling Shell"
    gsettings set org.gnome.shell.extensions.tilingshell snap-assistant-threshold 5
  else
    echo "⏳ Tiling Shell schema not available yet (login required)"
  fi
}

# --------------------------------------------------
clean_extensions() {
  echo "🧼 Removing GNOME extensions…"

  for UUID in "${EXTENSIONS[@]}"; do
    echo "❌ Removing $UUID"
    gnome-extensions disable "$UUID" 2>/dev/null || true
    rm -rf "$EXT_DIR/$UUID"
  done

  echo "🧠 Rebuilding schema cache"
  [[ -d "$SCHEMA_DIR" ]] && glib-compile-schemas "$SCHEMA_DIR" || true
}

# --------------------------------------------------
case "$ACTION" in
install)
  install_extensions
  ;;
config)
  config_extensions
  ;;
clean)
  clean_extensions
  ;;
all)
  install_extensions
  config_extensions
  ;;
*)
  echo "Usage: $0 [install|config|clean|all]"
  exit 1
  ;;
esac
