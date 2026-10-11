#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="powershell"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib.sh"
# shellcheck source=../lib.sh
source "$GLIMT_LIB"

ACTION="${1:-all}"

# Microsoft publishes PowerShell to packages.microsoft.com (PMC) as a universal
# RHEL rpm; Fedora has no PMC repo of its own, so we use the RHEL 9 channel.
# No version is pinned: every run installs or upgrades to the newest package
# in the repo. metadata_expire is kept short so `glimt update` sees new
# releases without this module having to call `dnf makecache`.
REPO_FILE="/etc/yum.repos.d/glimt-microsoft-powershell.repo"
# Repo file created by Microsoft's packages-microsoft-prod.rpm — if present,
# it already provides powershell and we don't add (or later remove) our own.
MS_PROD_REPO="/etc/yum.repos.d/microsoft-prod.repo"

# ------------------------------------------------------------
# Fedora / RHEL guard
# ------------------------------------------------------------
fedora_guard() {
  [[ -r /etc/os-release ]] || {
    echo "Error: /etc/os-release missing"
    exit 1
  }

  . /etc/os-release

  [[ "$ID" == "fedora" || "$ID" == "rhel" || "${ID_LIKE:-}" == *"fedora"* ]] || {
    echo "Error: Fedora/RHEL-based systems only."
    exit 1
  }
}

# PMC only ships x86_64 PowerShell rpms.
arch_supported() {
  if [[ "$(normalize_arch)" != "amd64" ]]; then
    warn "PowerShell rpms are only published for x86_64 — skipping on $(uname -m)."
    return 1
  fi
}

# ------------------------------------------------------------
# Dependencies + repo
# ------------------------------------------------------------
deps() {
  echo "[$MODULE_NAME] Installing dependencies and Microsoft repo…"
  arch_supported || return 0

  dnf_ensure curl

  if [[ -f "$MS_PROD_REPO" ]]; then
    echo "ℹ️  Microsoft prod repo already configured ($MS_PROD_REPO)."
    return 0
  fi

  if [[ ! -f "$REPO_FILE" ]]; then
    echo "Adding Microsoft PowerShell yum repo…"
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  else
    echo "ℹ️  Refreshing Microsoft PowerShell repo definition…"
  fi

  # Always (re)write so changes to the definition propagate on update.
  sudo tee "$REPO_FILE" >/dev/null <<'EOF'
[glimt-microsoft-powershell]
name=Microsoft PowerShell (packages.microsoft.com, RHEL 9)
baseurl=https://packages.microsoft.com/rhel/9/prod/
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
includepkgs=powershell*
metadata_expire=1h
EOF
}

# ------------------------------------------------------------
# Install / upgrade to latest
# ------------------------------------------------------------
install_pkg() {
  arch_supported || return 0

  echo "[$MODULE_NAME] Installing or updating PowerShell…"
  dnf_ensure powershell

  verify_binary pwsh --version || true
  echo "PowerShell $(rpm -q --qf '%{VERSION}' powershell 2>/dev/null || echo '?') installed."
}

# ------------------------------------------------------------
# Config (placeholder)
# ------------------------------------------------------------
config() {
  echo "[$MODULE_NAME] No extra PowerShell config (package defaults)."
}

# ------------------------------------------------------------
# Clean
# ------------------------------------------------------------
clean() {
  echo "[$MODULE_NAME] Removing PowerShell…"
  sudo dnf remove -y powershell || true
  # Only remove the repo glimt added; leave Microsoft's own repo package alone.
  sudo rm -f "$REPO_FILE"
}

# ------------------------------------------------------------
# All
# ------------------------------------------------------------
all() {
  deps
  install_pkg
  config
  echo "[$MODULE_NAME] Done."
}

# ------------------------------------------------------------
# Entrypoint
# ------------------------------------------------------------
fedora_guard

case "$ACTION" in
deps) deps ;;
install) install_pkg ;;
config) config ;;
clean) clean ;;
all) all ;;
*)
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 2
  ;;
esac
