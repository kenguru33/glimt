#!/bin/bash
set -e

MODULE_NAME="gnome-extensions"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
EXT_DIR="$HOME_DIR/.local/share/gnome-shell/extensions"
TMP_ZIP="/tmp/ext.zip"
GNOME_VERSION=$(gnome-shell --version | awk '{print $3}')
EXTENSIONS=(
  "blur-my-shell@aunetx"
  "rounded-window-corners@fxgn"
  "tilingshell@ferrarodomenico.com"
)
TO_ENABLE_AFTER_LOGIN=()
ACTION="${1:-all}"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
else
  echo "❌ Cannot detect OS."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "❌ This module supports Fedora/RHEL-based systems only."
  exit 1
fi

# === Define DEPS ===
DEPS=(curl unzip jq gnome-extensions-app dconf)

install_deps() {
  echo "📦 Installing dependencies for $OS_ID..."
  sudo dnf makecache -y
  sudo dnf install -y "${DEPS[@]}"
}

# === GNOME Extension Install ===

reload_gnome_shell() {
  echo -e "\n🔁 Extensions installed.\n🚨 Please log out and back in to complete activation.\n"
}

enable_extension_safely() {
  local uuid="$1"
  if gnome-extensions list | grep -q "$uuid"; then
    echo "✅ Enabling $uuid"
    sudo -u "$REAL_USER" gnome-extensions enable "$uuid" && echo "🟢 $uuid enabled."
  else
    echo "⚠️ $uuid is not yet registered. Will be enabled after login."
    TO_ENABLE_AFTER_LOGIN+=("$uuid")
  fi
}

install_extensions() {
  echo "🧩 Installing GNOME extensions..."
  sudo -u "$REAL_USER" mkdir -p "$EXT_DIR"

  for EXT_ID in "${EXTENSIONS[@]}"; do
    echo "🌐 Searching for $EXT_ID..."
    METADATA=$(curl -s "https://extensions.gnome.org/extension-query/?search=${EXT_ID}" | jq -r --arg uuid "$EXT_ID" '.extensions[] | select(.uuid == $uuid)')

    [[ -z "$METADATA" ]] && echo "❌ Extension $EXT_ID not found." && continue

    PK_ID=$(echo "$METADATA" | jq -r '.pk')
    VERSION_JSON=$(curl -s "https://extensions.gnome.org/extension-info/?pk=${PK_ID}&shell_version=${GNOME_VERSION}")
    DL_URL="https://extensions.gnome.org$(echo "$VERSION_JSON" | jq -r '.download_url')"

    echo "⬇️ Downloading $EXT_ID..."
    curl -sL "$DL_URL" -o "$TMP_ZIP"

    TMP_UNPACK=$(mktemp -d)
    unzip -oq "$TMP_ZIP" -d "$TMP_UNPACK"

    METADATA_PATH=$(find "$TMP_UNPACK" -type f -name metadata.json | head -n1)
    [[ -z "$METADATA_PATH" ]] && echo "❌ metadata.json not found" && continue

    ACTUAL_UUID=$(jq -r '.uuid' "$METADATA_PATH")
    [[ -z "$ACTUAL_UUID" || "$ACTUAL_UUID" == "null" ]] && echo "❌ UUID missing" && continue

    DEST="$EXT_DIR/$ACTUAL_UUID"
    EXT_ROOT="$(dirname "$METADATA_PATH")"

    echo "📁 Installing to $DEST"
    sudo -u "$REAL_USER" rm -rf "$DEST"
    sudo -u "$REAL_USER" mkdir -p "$DEST"
    sudo -u "$REAL_USER" cp -r "$EXT_ROOT"/* "$DEST"

    if [[ -d "$DEST/schemas" ]]; then
      echo "🔧 Compiling schemas..."
      sudo -u "$REAL_USER" glib-compile-schemas "$DEST/schemas"
      sudo -u "$REAL_USER" mkdir -p "$HOME_DIR/.local/share/glib-2.0/schemas"
      sudo -u "$REAL_USER" find "$DEST/schemas" -name '*.gschema.xml' -exec cp {} "$HOME_DIR/.local/share/glib-2.0/schemas/" \;
    fi

    enable_extension_safely "$ACTUAL_UUID"
  done

  if [[ -d "$HOME_DIR/.local/share/glib-2.0/schemas" ]]; then
    echo "🧠 Recompiling user schema directory..."
    sudo -u "$REAL_USER" glib-compile-schemas "$HOME_DIR/.local/share/glib-2.0/schemas/"
  fi

  if [[ ${#TO_ENABLE_AFTER_LOGIN[@]} -gt 0 ]]; then
    echo "💾 Updating enabled-extensions GSettings list..."
    CURRENT=$(sudo -u "$REAL_USER" gsettings get org.gnome.shell enabled-extensions 2>/dev/null | jq -c '.' 2>/dev/null || echo '[]')
    for uuid in "${TO_ENABLE_AFTER_LOGIN[@]}"; do
      CURRENT=$(echo "$CURRENT" | jq -c "unique + [\"$uuid\"]")
    done
    sudo -u "$REAL_USER" gsettings set org.gnome.shell enabled-extensions "$CURRENT"
  fi

  reload_gnome_shell
}

config_extensions() {
  echo "⚙️ Configuring installed extensions..."

  export GSETTINGS_SCHEMA_DIR="$HOME_DIR/.local/share/glib-2.0/schemas"

  echo "🎨 Blur My Shell"
  sudo -u "$REAL_USER" gsettings set org.gnome.shell.extensions.blur-my-shell brightness 0.8
  sudo -u "$REAL_USER" gsettings set org.gnome.shell.extensions.blur-my-shell sigma 30
  sudo -u "$REAL_USER" gsettings set org.gnome.shell.extensions.blur-my-shell color-and-noise true
  sudo -u "$REAL_USER" gsettings set org.gnome.shell.extensions.blur-my-shell hacks-level 1

  if command -v dconf >/dev/null 2>&1; then
    sudo -u "$REAL_USER" dconf write /org/gnome/shell/extensions/blur-my-shell/panel/override-background-dynamically false || true
  fi

  echo "🪟 Tiling Shell"
  sudo -u "$REAL_USER" gsettings set org.gnome.shell.extensions.tilingshell snap-assistant-threshold "5"
}

clean_extensions() {
  echo "🧼 Removing extensions..."
  for EXT_ID in "${EXTENSIONS[@]}"; do
    METADATA=$(curl -s "https://extensions.gnome.org/extension-query/?search=${EXT_ID}" | jq -r --arg uuid "$EXT_ID" '.extensions[] | select(.uuid == $uuid)')
    [[ -z "$METADATA" ]] && continue

    PK_ID=$(echo "$METADATA" | jq -r '.pk')
    VERSION_JSON=$(curl -s "https://extensions.gnome.org/extension-info/?pk=${PK_ID}&shell_version=${GNOME_VERSION}")
    DL_URL="https://extensions.gnome.org$(echo "$VERSION_JSON" | jq -r '.download_url')"

    curl -sL "$DL_URL" -o "$TMP_ZIP"
    TMP_UNPACK=$(mktemp -d)
    unzip -oq "$TMP_ZIP" -d "$TMP_UNPACK"
    METADATA_PATH=$(find "$TMP_UNPACK" -type f -name metadata.json | head -n1)
    ACTUAL_UUID=$(jq -r '.uuid' "$METADATA_PATH")

    echo "❌ Removing $ACTUAL_UUID"
    sudo -u "$REAL_USER" gnome-extensions disable "$ACTUAL_UUID" 2>/dev/null || true
    sudo -u "$REAL_USER" rm -rf "$EXT_DIR/$ACTUAL_UUID"
  done
}

# === Main Dispatcher ===
case "$ACTION" in
deps)
  install_deps
  ;;
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
  install_deps
  install_extensions
  config_extensions
  ;;
*)
  echo "Usage: $0 [deps|install|config|clean|all]"
  exit 1
  ;;
esac


