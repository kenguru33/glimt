#!/bin/bash
set -e
trap 'echo "❌ Discord installation failed. Exiting." >&2' ERR

MODULE_NAME="discord"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"

DISCORD_DEB_URL="https://discord.com/api/download?platform=linux&format=deb"
TMP_DEB="/tmp/discord_latest.deb"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]] || {
        echo "❌ This script supports Debian-based systems only."
        exit 1
    }
else
    echo "❌ Cannot detect OS. /etc/os-release missing."
    exit 1
fi

# === Dependencies ===
DEPS=(curl wget libatomic1 libappindicator3-1 libc++1)

install_deps() {
    echo "📦 Installing dependencies..."
    sudo apt update
    sudo apt install -y "${DEPS[@]}"
}

install_discord() {
    echo "⬇️  Downloading Discord..."
    
    # Try curl first (handles redirects better), then wget
    if command -v curl >/dev/null 2>&1; then
        curl -L "$DISCORD_DEB_URL" -o "$TMP_DEB"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$TMP_DEB" "$DISCORD_DEB_URL"
    else
        echo "❌ Neither curl nor wget found. Please install one."
        exit 1
    fi
    
    # Verify it's actually a .deb file
    if ! file "$TMP_DEB" | grep -q "Debian\|ar archive"; then
        echo "❌ Downloaded file is not a valid .deb package. It might be HTML/redirect."
        echo "   File type: $(file "$TMP_DEB")"
        rm -f "$TMP_DEB"
        exit 1
    fi

    echo "📦 Installing Discord..."
    sudo apt install -y "$TMP_DEB"

    echo "🧹 Cleaning up..."
    rm -f "$TMP_DEB"
    echo "✅ Discord installed."
}

config_discord() {
    echo "⚙️  Configuring Discord..."
    # Optional: Force Wayland
    # sudo sed -i 's|Exec=/usr/share/discord/Discord|Exec=/usr/share/discord/Discord --ozone-platform=wayland|g' /usr/share/applications/discord.desktop
}

clean_discord() {
    echo "🗑️  Removing Discord..."
    sudo apt purge -y discord
    sudo apt autoremove -y
}

case "$ACTION" in
    deps)
        install_deps
        ;;
    install)
        install_discord
        ;;
    config)
        config_discord
        ;;
    clean)
        clean_discord
        ;;
    all)
        install_deps
        install_discord
        config_discord
        ;;
    *)
        echo "Usage: $0 [all|deps|install|config|clean]"
        exit 1
        ;;
esac
