#!/bin/bash
set -e
trap 'echo "❌ Blackbox Terminal install failed. Exiting." >&2' ERR

MODULE_NAME="blackbox-terminal"
ACTION="${1:-all}"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* ]]; then
  echo "❌ This script supports Fedora only."
  exit 1
fi

# === Dependencies ===
deps() {
  echo "📦 Installing Blackbox Terminal..."
  sudo dnf makecache -y
  
  # Blackbox is available via Flatpak on Fedora
  if command -v flatpak >/dev/null 2>&1; then
    if ! flatpak list | grep -q "com.raggesilver.BlackBox"; then
      echo "📦 Installing Blackbox via Flatpak..."
      flatpak install -y flathub com.raggesilver.BlackBox
    else
      echo "✅ Blackbox already installed."
    fi
  else
    echo "⚠️  Flatpak not available. Please install flatpak first."
    echo "   Run: sudo dnf install -y flatpak"
    exit 1
  fi
}

# === Install ===
install() {
  echo "✅ Blackbox Terminal installation handled by deps."
}

# === Config ===
config() {
  echo "✅ Blackbox Terminal configured."
}

# === Clean ===
clean() {
  echo "🧹 Removing Blackbox Terminal..."
  
  if command -v flatpak >/dev/null 2>&1; then
    if flatpak list | grep -q "com.raggesilver.BlackBox"; then
      flatpak uninstall -y com.raggesilver.BlackBox
      echo "✅ Blackbox Terminal removed."
    else
      echo "ℹ️  Blackbox Terminal not installed."
    fi
  fi
}

# === Entry Point ===
case "$ACTION" in
  all)    deps; install; config ;;
  deps)   deps ;;
  install) install ;;
  config) config ;;
  clean)  clean ;;
  *)
    echo "❌ Unknown action: $ACTION"
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

