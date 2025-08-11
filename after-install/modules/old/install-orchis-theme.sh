#!/bin/bash
set -e
trap 'echo "❌ Something went wrong. Exiting." >&2' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME_DIR="${THEME_DIR:-orchis}"
THEME_COLOR="dark"
THEME_SHELL_COLOR="Dark"
THEME_BACKGROUND="background.jpg"
THEME_TWEAKS="macos"

THEME_PATH="$SCRIPT_DIR/$THEME_DIR"
BACKGROUND_ORG_PATH="$THEME_PATH/$THEME_BACKGROUND"
BACKGROUND_DEST_DIR="$HOME/.local/share/backgrounds"
BACKGROUND_DEST_PATH="$BACKGROUND_DEST_DIR/${THEME_DIR}-${THEME_BACKGROUND}"

[[ -f "$THEME_PATH/${THEME_DIR}.sh" ]] && source "$THEME_PATH/${THEME_DIR}.sh"

install_theme_packages() {
  echo "📦 Installing required theme packages..."
  sudo apt update
  sudo apt install -y gnome-tweaks gnome-shell-extensions dconf-cli git gtk2-engines-murrine sassc unzip jq
  echo "✅ Packages installed."
}

install_theme_assets() {
  echo "🎨 Installing Orchis GTK and Tela icon themes..."
  mkdir -p ~/.themes ~/.icons

  if [ ! -d /tmp/Orchis-theme ]; then
    git clone https://github.com/vinceliuice/Orchis-theme.git /tmp/Orchis-theme
  fi
  /tmp/Orchis-theme/install.sh --tweaks "$THEME_TWEAKS" -l 

  if [ ! -d /tmp/Tela-icon-theme ]; then
    git clone https://github.com/vinceliuice/Tela-icon-theme.git /tmp/Tela-icon-theme
  fi
  /tmp/Tela-icon-theme/install.sh -d ~/.icons

  echo "✅ Themes installed."
}

ensure_user_themes_extension() {
  EXT_UUID="user-theme@gnome-shell-extensions.gcampax.github.com"
  EXT_DIR="$HOME/.local/share/gnome-shell/extensions/$EXT_UUID"

  if gnome-extensions list | grep -q "$EXT_UUID"; then
    echo "✅ User Themes extension already installed."
    return
  fi

  echo "🔌 Installing User Themes extension..."

  # Get GNOME Shell version
  GNOME_VERSION=$(gnome-shell --version | awk '{print $3}' | cut -d. -f1,2)
  META=$(curl -s "https://extensions.gnome.org/extension-query/?search=user-theme" | jq -r '.extensions[] | select(.uuid=="'"$EXT_UUID"'")')

  if [[ -z "$META" ]]; then
    echo "❌ Failed to fetch metadata for User Themes extension."
    return
  fi

  PK=$(echo "$META" | jq -r '.pk')
  INFO=$(curl -s "https://extensions.gnome.org/extension-info/?pk=${PK}&shell_version=${GNOME_VERSION}")
  DL_URL="https://extensions.gnome.org$(echo "$INFO" | jq -r '.download_url')"

  if [[ "$DL_URL" == "null" ]]; then
    echo "❌ Failed to resolve download URL for GNOME $GNOME_VERSION"
    return
  fi

  TMP_ZIP=$(mktemp)
  curl -sL "$DL_URL" -o "$TMP_ZIP"

  mkdir -p "$EXT_DIR"
  unzip -oq "$TMP_ZIP" -d "$EXT_DIR"
  rm -f "$TMP_ZIP"

  if [[ -d "$EXT_DIR/schemas" ]]; then
    echo "🔧 Compiling schemas..."
    glib-compile-schemas "$EXT_DIR/schemas"
  fi

  echo "✅ User Themes extension installed."
}

apply_theme_config() {
  echo "🎛️ Applying GNOME settings..."

  gsettings set org.gnome.desktop.interface gtk-theme "Orchis-$THEME_COLOR"
  gsettings set org.gnome.desktop.interface icon-theme "Tela-$THEME_COLOR"
  gsettings set org.gnome.desktop.interface cursor-theme "Yaru"
  gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
  gsettings set org.gnome.desktop.wm.preferences theme "Orchis-$THEME_SHELL_COLOR"

  mkdir -p "$BACKGROUND_DEST_DIR"
  if [[ -f "$BACKGROUND_ORG_PATH" ]]; then
    cp -u "$BACKGROUND_ORG_PATH" "$BACKGROUND_DEST_PATH"
    gsettings set org.gnome.desktop.background picture-uri "file://$BACKGROUND_DEST_PATH"
    gsettings set org.gnome.desktop.background picture-uri-dark "file://$BACKGROUND_DEST_PATH"
    gsettings set org.gnome.desktop.background picture-options 'zoom'
  else
    echo "⚠️ Background not found: $BACKGROUND_ORG_PATH"
  fi

  EXT_UUID="user-theme@gnome-shell-extensions.gcampax.github.com"
  if gnome-extensions list | grep -q "$EXT_UUID"; then
    echo "🔁 Enabling User Themes extension..."
    gnome-extensions enable "$EXT_UUID" || true
    sleep 1
    gsettings set org.gnome.shell.extensions.user-theme name "Orchis-$THEME_SHELL_COLOR"
    echo "✅ Shell theme applied and extension enabled."
  else
    echo "❌ User Themes extension not found. Cannot apply shell theme."
  fi

  gsettings set org.gnome.desktop.wm.preferences button-layout 'appmenu:minimize,maximize,close'

  echo "✅ GNOME theme configuration complete."
}

clean_theme() {
  echo "🧹 Cleaning up themes..."
  rm -rf ~/.themes/Orchis* ~/.icons/Tela* "$BACKGROUND_DEST_PATH"
  echo "✅ Theme files removed. Please reset GNOME appearance manually if needed."
}

show_help() {
  echo "Usage: $0 [all|install|config|clean]"
  echo ""
  echo "  all      Install dependencies, themes, and apply settings"
  echo "  install  Install theme packages and assets only"
  echo "  config   Apply GTK, icon, shell theme and wallpaper"
  echo "  clean    Remove installed theme assets"
}

# === Main ===
case "$1" in
  all)
    install_theme_packages
    install_theme_assets
    ensure_user_themes_extension
    apply_theme_config
    ;;
  install)
    install_theme_packages
    install_theme_assets
    ensure_user_themes_extension
    ;;
  config)
    ensure_user_themes_extension
    apply_theme_config
    ;;
  clean)
    clean_theme
    ;;
  *)
    show_help
    ;;
esac
