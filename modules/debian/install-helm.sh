#!/usr/bin/env bash
# Glimt module: Install Kubernetes Helm (APT repo) on Debian.
# Actions: all | deps | install | config | clean

set -Eeuo pipefail

MODULE_NAME="helm"
ACTION="${1:-all}"

log(){ printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

# ----- Debian-only guard -----
deb_guard(){
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    [[ "$ID" == "debian" || "$ID_LIKE" == *"debian"* ]] || die "Debian-only module."
  else
    die "Cannot detect OS."
  fi
}

# ----- Real user context (avoid writing into /root) -----
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
ZSH_COMP_DIR="$REAL_HOME/.zsh/completions"              # your fpath
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MODULE_CONF_SRC="$SCRIPT_DIR/config/helm.zsh"           # modules/debian/config/helm.zsh
MODULE_CONF_DST="$REAL_HOME/.zsh/config/helm.zsh"

# ----- Helm APT repo -----
KEY_URL="https://baltocdn.com/helm/signing.asc"
KEYRING_DIR="/etc/apt/keyrings"
KEYRING_FILE="$KEYRING_DIR/helm.gpg"
LIST_FILE="/etc/apt/sources.list.d/helm-stable-debian.list"
APT_ARCH="$(dpkg --print-architecture)"
APT_LINE="deb [arch=${APT_ARCH} signed-by=${KEYRING_FILE}] https://baltocdn.com/helm/stable/debian/ all main"

install_deps(){
  log "Installing dependencies (sudo): curl gpg ca-certificates apt-transport-https"
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends curl gpg ca-certificates apt-transport-https
}

setup_repo(){
  log "Configuring Helm APT repository"
  sudo install -d -m 0755 "$KEYRING_DIR"
  curl -fsSL "$KEY_URL" | sudo gpg --dearmor --yes -o "$KEYRING_FILE"
  sudo chmod 0644 "$KEYRING_FILE"
  echo "$APT_LINE" | sudo tee "$LIST_FILE" >/dev/null
  sudo chmod 0644 "$LIST_FILE"
}

install_helm(){
  setup_repo
  log "Installing helm"
  sudo apt-get update -y
  sudo apt-get install -y helm
  log "Installed: $(helm version --short 2>/dev/null || echo 'helm')"
}

configure_helm(){
  if ! command -v helm >/dev/null 2>&1; then
    log "helm not found in PATH; skipping completions."
    return 0
  fi

  log "Generating Zsh completion → $ZSH_COMP_DIR/_helm"
  sudo -u "$REAL_USER" mkdir -p "$ZSH_COMP_DIR"
  # Generate completion as the real user to avoid root-owned files
  if sudo -u "$REAL_USER" bash -lc "helm completion zsh > '$ZSH_COMP_DIR/_helm'"; then
    chmod 755 "$REAL_HOME/.zsh" "$ZSH_COMP_DIR" 2>/dev/null || true
    chmod 644 "$ZSH_COMP_DIR/_helm" || true
    chown -R "$REAL_USER":"$REAL_USER" "$REAL_HOME/.zsh" 2>/dev/null || true
    log "Completions written: $ZSH_COMP_DIR/_helm"
  else
    die "Failed to generate Helm Zsh completion"
  fi

  # Optional: copy module config if you keep one under modules/debian/config/helm.zsh
  if [[ -f "$MODULE_CONF_SRC" ]]; then
    log "Installing Zsh config → $MODULE_CONF_DST"
    sudo -u "$REAL_USER" mkdir -p "$(dirname "$MODULE_CONF_DST")"
    install -m 0644 -o "$REAL_USER" -g "$REAL_USER" "$MODULE_CONF_SRC" "$MODULE_CONF_DST"
  else
    log "No module config found at $MODULE_CONF_SRC (skipping)."
  fi
}

clean_helm(){
  log "Removing helm and repository"
  sudo apt-get remove -y --purge helm || true
  sudo rm -f "$LIST_FILE" "$KEYRING_FILE" || true
  sudo apt-get update -y || true

  log "Removing Zsh completion and config"
  rm -f "$ZSH_COMP_DIR/_helm" 2>/dev/null || true
  rm -f "$MODULE_CONF_DST" 2>/dev/null || true
  log "Clean complete."
}

# ----- Entry point -----
deb_guard
case "$ACTION" in
  deps)    install_deps ;;
  install) install_deps; install_helm ;;
  config)  configure_helm ;;
  clean)   clean_helm ;;
  all)     install_deps; install_helm; configure_helm ;;
  *) echo "Usage: $0 [all|deps|install|config|clean]"; exit 1 ;;
esac

log "Done: $ACTION"
