#!/bin/bash
# Glimt module: prereq (Prerequisites via rpm-ostree)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail

# Error handler - only show errors for actual failures, not expected conditions
error_handler() {
  local exit_code=$?
  # Skip error message for functions that handle their own errors gracefully
  local current_func="${FUNCNAME[1]:-}"
  if [[ "$current_func" != "install_packages" && "$current_func" != "config" && "$current_func" != "load_package_metadata" ]]; then
    echo "❌ prereq module failed." >&2
  fi
  return $exit_code
}

trap 'error_handler' ERR

MODULE_NAME="prereq"
ACTION="${1:-all}"

REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$SCRIPT_DIR"
PACKAGES_TXT="$PACKAGES_DIR/rpm-ostree-packages.txt"
PACKAGES_JSON="$PACKAGES_DIR/packages.json"

log() {
  printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2
}

# Load packages from packages folder
load_packages() {
  local packages=()
  
  # Try to load from text file first (simpler, more reliable)
  if [[ -f "$PACKAGES_TXT" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      # Skip comments and empty lines
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${line// }" ]] && continue
      packages+=("$line")
    done < "$PACKAGES_TXT"
  fi
  
  # Fallback: try to extract from JSON if text file doesn't exist or is empty
  if [[ ${#packages[@]} -eq 0 && -f "$PACKAGES_JSON" ]] && command -v jq &>/dev/null; then
    while IFS= read -r pkg; do
      [[ -n "$pkg" ]] && packages+=("$pkg")
    done < <(jq -r '.rpm-ostree-packages[].name' "$PACKAGES_JSON" 2>/dev/null)
  fi
  
  # Final fallback: hardcoded list
  if [[ ${#packages[@]} -eq 0 ]]; then
    log "⚠️  Could not load packages from files, using fallback list"
    packages=("curl" "jq" "zsh" "wl-clipboard" "1password")
  fi
  
  printf '%s\n' "${packages[@]}"
}

# Load package metadata from JSON
load_package_metadata() {
  local pkg_name="$1"
  local key="$2"
  
  if [[ -f "$PACKAGES_JSON" ]] && command -v jq &>/dev/null 2>&1; then
    jq -r --arg name "$pkg_name" --arg key "$key" \
      '.rpm-ostree-packages[] | select(.name == $name) | .[$key] // empty' \
      "$PACKAGES_JSON" 2>/dev/null || true
  fi
}

# Initialize packages array
mapfile -t PACKAGES < <(load_packages)

require_user() {
  if [[ "$EUID" -eq 0 && -z "${SUDO_USER:-}" ]]; then
    echo "❌ Do not run this module as root directly." >&2
    exit 1
  fi
}

# === OS Check ===
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
else
  log "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* ]]; then
  log "❌ This script supports Fedora-based systems only."
  exit 1
fi

deps() {
  log "📦 Checking dependencies..."
  log "✅ No additional dependencies required (packages will be installed via rpm-ostree)"
}

install_repos() {
  # Check which packages require repositories
  for pkg in "${PACKAGES[@]}"; do
    local requires_repo
    requires_repo=$(load_package_metadata "$pkg" "requires_repository")
    
    if [[ "$requires_repo" == "true" ]]; then
      log "🔑 Setting up repository for $pkg..."
      
      # Try to get repository info from JSON
      local repo_name repo_gpg_key_url repo_url
      repo_name=$(load_package_metadata "$pkg" "repository.name")
      repo_gpg_key_url=$(load_package_metadata "$pkg" "repository.gpg_key_url")
      repo_url=$(load_package_metadata "$pkg" "repository.repo_url")
      
      # Fallback for 1password (most common case)
      if [[ "$pkg" == "1password" ]]; then
        repo_name="${repo_name:-1password}"
        repo_gpg_key_url="${repo_gpg_key_url:-https://downloads.1password.com/linux/keys/1password.asc}"
        repo_url="${repo_url:-https://downloads.1password.com/linux/rpm/stable}"
      fi
      
      if [[ -z "$repo_name" || -z "$repo_gpg_key_url" || -z "$repo_url" ]]; then
        log "⚠️  Repository information not found for $pkg, skipping repository setup"
        continue
      fi
      
      local gpg_key="/etc/pki/rpm-gpg/RPM-GPG-KEY-$repo_name"
      local repo_file="/etc/yum.repos.d/$repo_name.repo"
      
      if [[ ! -f "$gpg_key" ]]; then
        if command -v curl &>/dev/null; then
          curl -sS "$repo_gpg_key_url" | sudo tee "$gpg_key" >/dev/null
          log "✅ $pkg GPG key imported"
        else
          log "❌ curl not available, cannot import GPG key for $pkg"
          return 1
        fi
      else
        log "ℹ️  $pkg GPG key already present"
      fi
      
      if [[ ! -f "$repo_file" ]]; then
        sudo tee "$repo_file" >/dev/null <<EOF
[$repo_name]
name=$repo_name Stable Channel
baseurl=$repo_url/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=file://$gpg_key
EOF
        log "✅ $pkg repository added"
      else
        log "ℹ️  $pkg repository already configured"
      fi
    fi
  done
}

install_packages() {
  log "🔌 Installing prerequisite packages via rpm-ostree..."
  
  local packages_to_install=()
  local packages_already_installed=()
  local packages_pending=()
  
  # Check which packages need to be installed (expected failures are OK)
  for pkg in "${PACKAGES[@]}"; do
    if rpm -q "$pkg" &>/dev/null 2>&1; then
      packages_already_installed+=("$pkg")
    else
      packages_to_install+=("$pkg")
    fi
  done || true
  
  # Report already installed packages
  if [[ ${#packages_already_installed[@]} -gt 0 ]]; then
    log "✅ Already installed: ${packages_already_installed[*]}"
  fi
  
  # Install packages that need installation
  if [[ ${#packages_to_install[@]} -eq 0 ]]; then
    log "✅ All prerequisite packages are already installed"
    return 0
  fi
  
  log "⬇️  Installing packages: ${packages_to_install[*]}"
  
  local install_failed=0
  for pkg in "${packages_to_install[@]}"; do
    log "   Installing $pkg..."
    local output
    output=$(sudo rpm-ostree install -y "$pkg" 2>&1) || {
      if echo "$output" | grep -q "already requested"; then
        log "   ✅ $pkg already requested in pending layer"
        packages_pending+=("$pkg")
      else
        log "   ❌ Failed to install $pkg:"
        echo "$output" >&2
        install_failed=1
      fi
    }
    if [[ ! " ${packages_pending[@]} " =~ " ${pkg} " ]] && [[ $install_failed -eq 0 ]]; then
      log "   ✅ $pkg installed"
    fi
  done
  
  if [[ $install_failed -eq 1 ]]; then
    return 1
  fi
  
  log "✅ All packages processed"
  if [[ ${#packages_pending[@]} -gt 0 ]] || [[ ${#packages_to_install[@]} -gt 0 ]]; then
    log "ℹ️  A system reboot is required for rpm-ostree changes to take effect"
  fi
}

install() {
  # Set up repositories first (for packages that require them)
  install_repos
  
  install_packages
}

config() {
  require_user
  
  log "🔧 Verifying prerequisite packages installation..."
  
  local missing_packages=()
  local available_packages=()
  
  # Check packages (expected failures are OK)
  for pkg in "${PACKAGES[@]}"; do
    if rpm -q "$pkg" &>/dev/null 2>&1; then
      available_packages+=("$pkg")
    else
      missing_packages+=("$pkg")
    fi
  done || true
  
  if [[ ${#available_packages[@]} -gt 0 ]]; then
    log "✅ Installed packages: ${available_packages[*]}"
  fi
  
  if [[ ${#missing_packages[@]} -gt 0 ]]; then
    log "⚠️  Packages not yet available: ${missing_packages[*]}"
    log "ℹ️  A system reboot may be required for rpm-ostree changes to take effect"
  fi
  
  # Check if commands are available in PATH (expected failures are OK)
  log "🔍 Checking if commands are available in PATH..."
  
  # Build command mapping from packages
  declare -A cmd_map
  cmd_map["curl"]="curl"
  cmd_map["jq"]="jq"
  cmd_map["zsh"]="zsh"
  cmd_map["wl-clipboard"]="wl-copy"
  
  for pkg in "${PACKAGES[@]}"; do
    local cmd="${cmd_map[$pkg]:-$pkg}"
    if command -v "$cmd" &>/dev/null 2>&1; then
      log "   ✅ $cmd is available: $(command -v "$cmd")"
    else
      log "   ⚠️  $cmd not yet available in PATH (from $pkg)"
    fi
  done || true
  
  # Special case for wl-clipboard (has multiple commands)
  if [[ " ${PACKAGES[@]} " =~ " wl-clipboard " ]]; then
    for cmd in wl-copy wl-paste; do
      if command -v "$cmd" &>/dev/null 2>&1; then
        log "   ✅ $cmd is available: $(command -v "$cmd")"
      else
        log "   ⚠️  $cmd not yet available in PATH (from wl-clipboard)"
      fi
    done || true
  fi
  
  log "✅ Prerequisite packages configuration complete"
}

clean() {
  log "🧹 Removing prerequisite packages..."
  
  local packages_to_remove=()
  
  for pkg in "${PACKAGES[@]}"; do
    if rpm -q "$pkg" &>/dev/null; then
      packages_to_remove+=("$pkg")
    fi
  done
  
  if [[ ${#packages_to_remove[@]} -eq 0 ]]; then
    log "ℹ️  No prerequisite packages installed"
  else
    log "🔄 Uninstalling packages: ${packages_to_remove[*]}"
    for pkg in "${packages_to_remove[@]}"; do
      log "   Uninstalling $pkg..."
      sudo rpm-ostree uninstall "$pkg"
      log "   ✅ $pkg uninstalled"
    done
    log "ℹ️  A system reboot is required for the changes to take effect"
  fi
  
  # Clean up repositories for packages that require them
  for pkg in "${PACKAGES[@]}"; do
    local requires_repo
    requires_repo=$(load_package_metadata "$pkg" "requires_repository")
    
    if [[ "$requires_repo" == "true" ]]; then
      local repo_name
      repo_name=$(load_package_metadata "$pkg" "repository.name")
      
      # Fallback for 1password
      if [[ "$pkg" == "1password" ]]; then
        repo_name="${repo_name:-1password}"
      fi
      
      if [[ -n "$repo_name" ]]; then
        log "🧹 Removing $pkg repository configuration..."
        sudo rm -f "/etc/yum.repos.d/$repo_name.repo" "/etc/pki/rpm-gpg/RPM-GPG-KEY-$repo_name"
        log "✅ Repository removed"
      fi
    fi
  done
  
  log "✅ Clean complete"
}

case "$ACTION" in
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
all)
  deps
  install
  config
  ;;
*)
  echo "Usage: $0 {all|deps|install|config|clean}"
  exit 1
  ;;
esac
