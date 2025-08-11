#!/bin/bash
set -e

MODULE_NAME="system-update"
ACTION="${1:-all}"

# Detect OS
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="${ID,,}"
else
  echo "❌ Unable to detect operating system."
  exit 1
fi

update_debian() {
  echo "📦 Updating system (Debian/Ubuntu)..."
  sudo apt update
  sudo apt upgrade -y
  sudo apt full-upgrade -y
  sudo apt autoremove -y
  echo "✅ System updated (Debian-based)."
}

update_fedora() {
  echo "📦 Updating system (Fedora)..."
  sudo dnf upgrade --refresh -y
  sudo dnf autoremove -y
  echo "✅ System updated (Fedora-based)."
}

run_update() {
  case "$OS_ID" in
    debian|ubuntu|linuxmint)
      update_debian
      ;;
    fedora)
      update_fedora
      ;;
    *)
      echo "❌ Unsupported OS: $OS_ID"
      exit 1
      ;;
  esac
}

# === Entry Point ===
case "$ACTION" in
  deps)
    echo "ℹ️ No dependencies for $MODULE_NAME."
    ;;
  install)
    run_update
    ;;
  config)
    echo "ℹ️ No config required for $MODULE_NAME."
    ;;
  clean)
    echo "🧼 Nothing to clean for $MODULE_NAME."
    ;;
  all)
    run_update
    ;;
  *)
    echo "❌ Unknown action: $ACTION"
    exit 1
    ;;
esac
