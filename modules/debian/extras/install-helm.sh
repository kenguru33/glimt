#!/usr/bin/env bash
# modules/debian/install-helm.sh
# Glimt module: Install Kubernetes Helm (APT repo) on Debian.
# Actions: all | deps | install | config | clean
#
# - Uses the official Helm APT repo (baltocdn.com) with /etc/apt/keyrings
# - Installs helm via apt (no snaps/homebrew)
# - Generates Zsh/Bash completions if helm is present

set -Eeuo pipefail

MODULE_NAME="helm"
ACTION="${1:-all}"

log() { printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die() { printf "ERROR: %s\n" "$*" >&2; exit 1; }

# ---- Debian-only guard ----
deb_guard() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]] || die "Debian-only module."
  else
    die "Cannot detect OS."
  fi
}

# ---- Repo config ----
KEY_URL="https://baltocdn.com/helm/signing.asc"
KEYRING_DIR="/etc/apt/keyrings"
KEYRING_FILE="$KEYRING_DIR/helm.gpg"
LIST_FILE="/etc/apt/sources.list.d/helm-stable-debian.list"
APT_ARCH="$(dpkg --print-architecture)"
APT_LINE="deb [arch=${APT_ARCH} signed-by=${KEYRING_FILE}] https://baltocdn.com/helm/stable/debian/ all main"

install_deps() {
  log "Installing dependencies (sudo): curl, gpg, ca-certificates, apt-transport-https"
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends curl gpg ca-certificates apt-transport-https
}

setup_repo() {
  log "Configuring Helm APT repository"
  sudo install -d -m 0755 "$KEYRING_DIR"
  curl -fsSL "$KEY_URL" | sudo gpg --dearmor --yes -o "$KEYRING_FILE"
  sudo chmod 0644 "$KEYRING_FILE"
  echo "$APT_LINE" | sudo tee "$LIST_FILE" >/dev/null
  sudo chmod 0644 "$LIST_FILE"
}

install_helm() {
  setup_repo
  log "Installing helm"
  sudo apt-get update -y
  sudo apt-get install -y helm
  log "Installed: $(helm version --short 2>/dev/null || echo 'helm')"
}

configure_helm() {
  # Generate completions only if helm is installed and in PATH
  if command -v helm >/dev/null 2>&1; then
    # Zsh
    local zfunc="$HOME/.local/share/zsh/site-functions"
    mkdir -p "$zfunc"
    helm completion zsh > "$zfunc/_helm"
    # Bash
    local bcomp="$HOME/.bash_completion.d"
    mkdir -p "$bcomp"
    helm completion bash > "$bcomp/helm"
    log "Completions written: Zsh → $zfunc/_helm, Bash → $bcomp/helm"
  else
    log "helm not found in PATH; skipping completions."
  fi
}

clean_helm() {
  log "Removing helm and repository"
  sudo apt-get remove -y --purge helm || true
  sudo rm -f "$LIST_FILE" || true
  sudo rm -f "$KEYRING_FILE" || true
  sudo apt-get update -y || true
  log "Clean complete."
}

# ---- Entry point ----
deb_guard

case "$ACTION" in
  deps)
    install_deps
    ;;
  install)
    install_deps
    install_helm
    ;;
  config)
    configure_helm
    ;;
  clean)
    clean_helm
    ;;
  all)
    install_deps
    install_helm
    configure_helm
    ;;
  *)
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac

log "Done: $ACTION"
