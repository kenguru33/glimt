#!/bin/bash
set -e

MODULE_NAME="gnome-extensions"
EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
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

# === Define DEPS ===
DEPS=(curl unzip jq gnome-shell-extension-prefs dconf-cli)

install_deps() {
  echo "📦 Installing dependencies for $OS_ID..."
  if [[ "$OS_ID" == "debian" || "$ID_LIKE" == *"debian"* ]]; then
    sudo apt update
    sudo apt install -y "${DEPS[@]}"
  else
    echo "❌ Unsupported OS: $OS_ID. Only Debian-based systems are supported."
    exit 1
  fi
}

# === GNOME Extension Install ===

reload_gnome_shell() {
  echo -e "\n🔁 Extensions installed.\n🚨 Please log out and back in to complete activation.\n"
}

enable_extension_safely() {
  local uuid="$1"
  if gnome-extensions list | grep -q "$uuid"; then
    echo "✅ Enabling $uuid"
    gnome-extensions enable "$uuid" && echo "🟢 $uuid enabled."
  else
    echo "⚠️ $uuid is not yet registered. Will be enabled after login."
    TO_ENABLE_AFTER_LOGIN+=("$uuid")
  fi
}

install_extensions() {
  echo "🧩 Installing GNOME extensions..."
  mkdir -p "$EXT_DIR"

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
    rm -rf "$DEST"
    mkdir -p "$DEST"
    cp -r "$EXT_ROOT"/* "$DEST"

    if [[ -d "$DEST/schemas" ]]; then
      echo "🔧 Compiling schemas..."
      glib-compile-schemas "$DEST/schemas"
      mkdir -p ~/.local/share/glib-2.0/schemas
      find "$DEST/schemas" -name '*.gschema.xml' -exec cp {} ~/.local/share/glib-2.0/schemas/ \;
    fi

    enable_extension_safely "$ACTUAL_UUID"
  done

  if [[ -d ~/.local/share/glib-2.0/schemas ]]; then
    echo "🧠 Recompiling user schema directory..."
    glib-compile-schemas ~/.local/share/glib-2.0/schemas/
  fi

  if [[ ${#TO_ENABLE_AFTER_LOGIN[@]} -gt 0 ]]; then
    echo "💾 Updating enabled-extensions GSettings list..."
    CURRENT=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null | jq -c '.' 2>/dev/null || echo '[]')
    for uuid in "${TO_ENABLE_AFTER_LOGIN[@]}"; do
      CURRENT=$(echo "$CURRENT" | jq -c "unique + [\"$uuid\"]")
    done
    gsettings set org.gnome.shell enabled-extensions "$CURRENT"
  fi

  reload_gnome_shell
}

config_extensions() {
  echo "⚙️ Configuring installed extensions..."

  export GSETTINGS_SCHEMA_DIR="$HOME/.local/share/glib-2.0/schemas"

  echo "🎨 Blur My Shell"
  gsettings set org.gnome.shell.extensions.blur-my-shell brightness 0.8
  gsettings set org.gnome.shell.extensions.blur-my-shell sigma 30
  gsettings set org.gnome.shell.extensions.blur-my-shell color-and-noise true
  gsettings set org.gnome.shell.extensions.blur-my-shell hacks-level 1

  if command -v dconf &>/dev/null; then
    dconf write /org/gnome/shell/extensions/blur-my-shell/panel/override-background-dynamically false || true
  fi

  echo "🪟 Tiling Shell"
  gsettings set org.gnome.shell.extensions.tilingshell snap-assistant-threshold "5"
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
    gnome-extensions disable "$ACTUAL_UUID" 2>/dev/null || true
    rm -rf "$EXT_DIR/$ACTUAL_UUID"
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
