#!/bin/bash
set -e
trap 'echo "ERROR ❌ An error occurred. Exiting." >&2' ERR

MODULE_NAME="vscode"
ACTION="${1:-all}"

# === Detect OS ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

# === Step 1: Dependencies ===
install_dependencies() {
  echo "🔧 Installing dependencies..."

  if command -v apt &>/dev/null; then
    sudo apt update -qq
    sudo apt install -y curl gnupg
  elif command -v dnf &>/dev/null; then
    sudo dnf install -y curl gpg
  else
    echo "❌ Unsupported package manager."
    exit 1
  fi

  echo "✅ Dependencies installed."
}

# === Step 2: Install VS Code ===
install_vscode() {
  echo "🖥️ Installing VS Code..."

  if command -v code >/dev/null 2>&1; then
    echo "✅ VS Code is already installed."
    return
  fi

  if [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]]; then
    echo "🧹 Cleaning conflicting sources..."
    sudo rm -f /etc/apt/sources.list.d/code.list
    sudo rm -f /etc/apt/sources.list.d/vscode.list
    sudo rm -f /etc/apt/keyrings/microsoft.gpg
    sudo rm -f /usr/share/keyrings/microsoft.gpg

    echo "➕ Adding Microsoft GPG key and repo..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | \
      gpg --dearmor | sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | \
      sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null

    sudo apt update -qq
    sudo apt install -y code

  elif [[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* ]]; then
    echo "➕ Adding Microsoft GPG key and repo..."
    sudo tee /etc/yum.repos.d/vscode.repo > /dev/null <<EOF
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

    sudo dnf check-update || true
    sudo dnf install -y code

  else
    echo "❌ Unsupported OS: $ID"
    exit 1
  fi

  echo "✅ VS Code installed."
}

# === Step 3: Clean ===
cleanup() {
  echo "🧹 Cleaning up VS Code..."

  sudo rm -f /tmp/vscode.deb /tmp/vscode.rpm

  if command -v code &>/dev/null; then
    if command -v apt &>/dev/null; then
      sudo apt remove --purge -y code
      sudo rm -f /etc/apt/sources.list.d/vscode.list
      sudo rm -f /etc/apt/sources.list.d/code.list
      sudo rm -f /etc/apt/keyrings/microsoft.gpg
      sudo rm -f /usr/share/keyrings/microsoft.gpg
    elif command -v dnf &>/dev/null; then
      sudo dnf remove -y code
      sudo rm -f /etc/yum.repos.d/vscode.repo
    fi
  fi

  echo "✅ Cleanup complete."
}

# === Help ===
show_help() {
  echo "Usage: $0 [all|deps|install|clean]"
  echo ""
  echo "  all       Install dependencies + VS Code"
  echo "  deps      Install only required tools (curl, gpg)"
  echo "  install   Add repo + install VS Code"
  echo "  clean     Remove VS Code and repo/key"
}

# === Entry Point ===
case "$ACTION" in
  all)
    install_dependencies
    install_vscode
    ;;
  deps)
    install_dependencies
    ;;
  install)
    install_vscode
    ;;
  clean)
    cleanup
    ;;
  *)
    show_help
    ;;
esac
