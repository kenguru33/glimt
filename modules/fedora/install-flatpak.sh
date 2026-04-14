#!/bin/bash
set -Eeuo pipefail

MODULE_NAME="flatpak"
ACTION="${1:-all}"
trap 'echo "❌ [$MODULE_NAME] Error on line $LINENO" >&2' ERR

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

MODULE="flatpak"
REMOTE_NAME="flathub"
REMOTE_URL="https://flathub.org/repo/flathub.flatpakrepo"

# === OS Check (Fedora only) ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "❌ This module supports Fedora/RHEL-based systems only."
  exit 1
fi

install_deps() {
	echo "📦 Installing Flatpak dependencies..."
	sudo dnf install -y flatpak
}

install_flatpak() {
	echo "🔧 Installing Flatpak (core setup)..."
	sudo dnf install -y flatpak

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
	sudo dnf remove -y flatpak || true
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


