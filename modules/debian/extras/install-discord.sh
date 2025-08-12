#!/bin/bash
set -e
trap 'echo "❌ Discord installation failed. Exiting." >&2' ERR

MODULE_NAME="discord"
ACTION="${1:-all}"

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
    wget -O "$TMP_DEB" "$DISCORD_DEB_URL"

    echo "📦 Installing Discord..."
    sudo apt install -y "$TMP_DEB"

    echo "🧹 Cleaning up..."
    rm -f "$TMP_DEB"
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
