#!/bin/bash
# Glimt module: prereq (Prerequisites via rpm-ostree)
# Actions: all | deps | install | config | clean

set -Eeuo pipefail

# Error handler - only show errors for actual failures, not expected conditions
error_handler() {
  local exit_code=$?
  # Skip error message for functions that handle their own errors gracefully
  local current_func="${FUNCNAME[1]:-}"
  if [[ "$current_func" != "install_packages" && "$current_func" != "config" && "$current_func" != "load_package_metadata" && "$current_func" != "install_homebrew" && "$current_func" != "config_homebrew" ]]; then
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
        # For rpm-ostree, use URL-based gpgkey (more reliable than file path)
        # Also ensure GPG key is imported for verification
        if [[ "$pkg" == "1password" ]]; then
          # Use URL-based gpgkey for 1password (works better with rpm-ostree)
          sudo tee "$repo_file" >/dev/null <<EOF
[$repo_name]
name=$repo_name Stable Channel
baseurl=$repo_url/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$repo_gpg_key_url
EOF
        else
          # For other packages, use file-based gpgkey if available
          sudo tee "$repo_file" >/dev/null <<EOF
[$repo_name]
name=$repo_name Stable Channel
baseurl=$repo_url/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=0
gpgkey=file://$gpg_key
EOF
        fi
        log "✅ $pkg repository added"
        
        # Verify repository file was created correctly
        if [[ ! -f "$repo_file" ]]; then
          log "❌ Failed to create repository file: $repo_file"
          return 1
        fi
        
        # For 1password, verify the repository configuration
        if [[ "$pkg" == "1password" ]]; then
          log "🔍 Verifying 1password repository configuration..."
          if grep -q "baseurl.*1password.com" "$repo_file" 2>/dev/null; then
            log "✅ 1password repository URL verified"
          else
            log "⚠️  Warning: 1password repository URL may be incorrect"
          fi
        fi
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
      local exit_code=$?
      if echo "$output" | grep -q "already requested"; then
        log "   ✅ $pkg already requested in pending layer"
        packages_pending+=("$pkg")
      elif echo "$output" | grep -qi "no package"; then
        log "   ❌ Package $pkg not found in repositories"
        log "   ℹ️  This may indicate a repository configuration issue"
        if [[ "$pkg" == "1password" ]]; then
          log "   💡 For 1password, ensure the repository was set up correctly in install_repos()"
        fi
        echo "$output" >&2
        install_failed=1
      else
        log "   ❌ Failed to install $pkg (exit code: $exit_code):"
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

install_homebrew() {
  require_user
  
  local brew_prefix="$HOME_DIR/.linuxbrew"
  
  if [[ -x "$brew_prefix/bin/brew" ]]; then
    log "✅ Homebrew already installed"
    # Make brew available in current shell
    eval "$("$brew_prefix/bin/brew" shellenv)" 2>/dev/null || true
    export PATH="$brew_prefix/bin:$brew_prefix/sbin:$PATH"
    export HOMEBREW_PREFIX="$brew_prefix"
    export HOMEBREW_CELLAR="$brew_prefix/Cellar"
    export HOMEBREW_REPOSITORY="$brew_prefix/Homebrew"
    if command -v brew &>/dev/null 2>&1; then
      log "✅ brew is available in current shell: $(command -v brew)"
    fi
    return 0
  fi
  
  log "🍺 Installing Homebrew (user-space)..."
  
  # Check for required dependencies
  local missing_deps=()
  local required_commands=("curl" "file" "git")
  
  for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &>/dev/null 2>&1; then
      missing_deps+=("$cmd")
    fi
  done
  
  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    log "❌ Missing required dependencies for Homebrew: ${missing_deps[*]}"
    log "ℹ️  Please install these packages first via rpm-ostree"
    return 1
  fi
  
  # Run Homebrew installer with sudo
  NONINTERACTIVE=1 \
    sudo -u "$REAL_USER" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
    log "❌ Failed to install Homebrew"
    return 1
  }
  
  # Make brew available in current shell
  if [[ -x "$brew_prefix/bin/brew" ]]; then
    eval "$("$brew_prefix/bin/brew" shellenv)" 2>/dev/null || true
    export PATH="$brew_prefix/bin:$brew_prefix/sbin:$PATH"
    export HOMEBREW_PREFIX="$brew_prefix"
    export HOMEBREW_CELLAR="$brew_prefix/Cellar"
    export HOMEBREW_REPOSITORY="$brew_prefix/Homebrew"
    if command -v brew &>/dev/null 2>&1; then
      log "✅ Homebrew installed and available in current shell: $(command -v brew)"
    else
      log "✅ Homebrew installed (brew command may need shell restart)"
    fi
  else
    log "✅ Homebrew installed (may need to source shellenv manually)"
  fi
}

config_homebrew() {
  require_user
  
  local brew_prefix="$HOME_DIR/.linuxbrew"
  local env_dir="$HOME_DIR/.config/environment.d"
  local env_file="$env_dir/99-homebrew.conf"
  local zsh_config_dir="$HOME_DIR/.zsh/config"
  local zsh_file="$zsh_config_dir/homebrew.zsh"
  local bashrc_file="$HOME_DIR/.bashrc"
  
  if [[ ! -x "$brew_prefix/bin/brew" ]]; then
    log "⚠️  Homebrew not installed, skipping configuration"
    return 0
  fi
  
  log "🛠 Configuring Homebrew environment..."
  
  # Systemd user environment (for GUI apps)
  mkdir -p "$env_dir"
  cat >"$env_file" <<EOF
PATH=$brew_prefix/bin:$brew_prefix/sbin:\$PATH
HOMEBREW_PREFIX=$brew_prefix
HOMEBREW_CELLAR=$brew_prefix/Cellar
HOMEBREW_REPOSITORY=$brew_prefix/Homebrew
EOF
  chown "$REAL_USER:$REAL_USER" "$env_file"
  log "✅ Systemd environment config installed"
  
  # Bash configuration
  # Check if homebrew config already exists in bashrc
  if [[ ! -f "$bashrc_file" ]] || ! grep -q "Homebrew\|\.linuxbrew" "$bashrc_file" 2>/dev/null; then
    {
      echo ""
      echo "# Homebrew (Linuxbrew)"
      echo "if [[ -x \"\$HOME/.linuxbrew/bin/brew\" ]]; then"
      echo "  eval \"\$(\$HOME/.linuxbrew/bin/brew shellenv)\""
      echo "fi"
    } >> "$bashrc_file"
    chown "$REAL_USER:$REAL_USER" "$bashrc_file"
    log "✅ Bash config added to $bashrc_file"
  else
    log "ℹ️  Bash config already present in $bashrc_file"
  fi
  
  # Zsh configuration
  mkdir -p "$zsh_config_dir"
  cat >"$zsh_file" <<'EOF'
# Homebrew (Linuxbrew)
if [[ -x "$HOME/.linuxbrew/bin/brew" ]]; then
  eval "$($HOME/.linuxbrew/bin/brew shellenv)"
fi
EOF
  chown "$REAL_USER:$REAL_USER" "$zsh_file"
  log "✅ Zsh config installed: $zsh_file"
  
  log "ℹ️  Log out and back in (or reboot) for GUI apps to see Homebrew"
}

install() {
  # Set up repositories first (for packages that require them)
  install_repos
  
  install_packages
  
  # Install Homebrew after packages are installed
  install_homebrew
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
  # Note: Some packages (like 1password) may not have CLI commands or may not be
  # available until after reboot on Silverblue
  log "🔍 Checking if commands are available in PATH..."
  
  # Build command mapping from packages
  # Packages without CLI commands should be excluded from PATH checks
  declare -A cmd_map
  cmd_map["curl"]="curl"
  cmd_map["jq"]="jq"
  cmd_map["zsh"]="zsh"
  cmd_map["wl-clipboard"]="wl-copy"
  # 1password is a GUI app and may not have a CLI command, so we skip PATH check
  
  for pkg in "${PACKAGES[@]}"; do
    # Skip PATH check for packages that don't have CLI commands or are GUI apps
    if [[ "$pkg" == "1password" ]]; then
      # 1password is a GUI application - verify it's installed via rpm instead
      if rpm -q "$pkg" &>/dev/null 2>&1; then
        log "   ✅ $pkg package is installed (GUI app, no CLI command expected)"
      else
        log "   ⚠️  $pkg package not yet available (reboot may be required)"
      fi
      continue
    fi
    
    local cmd="${cmd_map[$pkg]:-}"
    # Only check PATH if we have a command mapping (skip packages without CLI commands)
    if [[ -z "$cmd" ]]; then
      continue
    fi
    
    # Check if command is available (non-failing check)
    if command -v "$cmd" &>/dev/null 2>&1; then
      log "   ✅ $cmd is available: $(command -v "$cmd")"
    else
      log "   ⚠️  $cmd not yet available in PATH (from $pkg - reboot may be required)"
    fi
  done || true
  
  # Special case for wl-clipboard (has multiple commands)
  if [[ " ${PACKAGES[@]} " =~ " wl-clipboard " ]]; then
    for cmd in wl-copy wl-paste; do
      if command -v "$cmd" &>/dev/null 2>&1; then
        log "   ✅ $cmd is available: $(command -v "$cmd")"
      else
        log "   ⚠️  $cmd not yet available in PATH (from wl-clipboard - reboot may be required)"
      fi
    done || true
  fi
  
  # Configure Homebrew
  config_homebrew
  
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
  
  # Clean up Homebrew
  require_user
  local brew_prefix="$HOME_DIR/.linuxbrew"
  local env_file="$HOME_DIR/.config/environment.d/99-homebrew.conf"
  local zsh_file="$HOME_DIR/.zsh/config/homebrew.zsh"
  local bashrc_file="$HOME_DIR/.bashrc"
  
  if [[ -d "$brew_prefix" ]]; then
    log "🧹 Removing Homebrew..."
    rm -rf "$brew_prefix"
    log "✅ Homebrew removed"
  fi
  
  if [[ -f "$env_file" ]]; then
    rm -f "$env_file"
    log "✅ Homebrew environment config removed"
  fi
  
  if [[ -f "$zsh_file" ]]; then
    rm -f "$zsh_file"
    log "✅ Homebrew zsh config removed"
  fi
  
  # Remove homebrew config from bashrc if it exists
  if [[ -f "$bashrc_file" ]]; then
    # Remove homebrew section from bashrc
    if grep -q "Homebrew\|\.linuxbrew" "$bashrc_file" 2>/dev/null; then
      # Use sed to remove the homebrew section (lines between "# Homebrew" comment and "fi")
      sed -i '/# Homebrew (Linuxbrew)/,/^fi$/d' "$bashrc_file" 2>/dev/null || true
      log "✅ Homebrew bash config removed from $bashrc_file"
    fi
  fi
  
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
