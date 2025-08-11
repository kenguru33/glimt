#!/bin/bash
set -e

ACTION="${1:-all}"
MODULE="flatpak"
REMOTE_NAME="flathub"
REMOTE_URL="https://flathub.org/repo/flathub.flatpakrepo"

install_deps() {
	echo "📦 Installing Flatpak dependencies..."
	sudo apt update
	sudo apt install -y flatpak gnome-software-plugin-flatpak
}

install_flatpak() {
	echo "🔧 Installing Flatpak (core setup)..."
	sudo apt install -y flatpak

	if ! flatpak remote-list | grep -q "^${REMOTE_NAME}"; then
		echo "🌐 Adding Flathub remote..."
		sudo flatpak remote-add --if-not-exists "$REMOTE_NAME" "$REMOTE_URL"
	else
		echo "✅ Flathub remote already added."
	fi
}

config_flatpak() {
	echo "⚙️  Ensuring Flathub is set up..."
	if ! flatpak remote-list | grep -q "^${REMOTE_NAME}"; then
		sudo flatpak remote-add --if-not-exists "$REMOTE_NAME" "$REMOTE_URL"
	fi
	echo "✅ Flatpak is configured with Flathub."
}

clean_flatpak() {
	echo "🧹 Removing Flatpak and Flathub..."
	sudo flatpak remote-delete "$REMOTE_NAME" || true
	sudo apt remove -y flatpak gnome-software-plugin-flatpak || true
	sudo apt autoremove -y
	echo "✅ Flatpak removed."
}

# === Entry point ===
case "$ACTION" in
deps)
	install_deps
	;;
install)
	install_flatpak
	;;
config)
	config_flatpak
	;;
clean)
	clean_flatpak
	;;
all)
	install_deps
	install_flatpak
	config_flatpak
	;;
*)
	echo "Usage: $0 {deps|install|config|clean|all}"
	exit 1
	;;
esac
