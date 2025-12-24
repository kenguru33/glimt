#!/usr/bin/env bash
# Glimt module: Install Kubernetes Helm (GitHub releases) on Fedora.
# Actions: all | deps | install | config | clean

set -Eeuo pipefail

MODULE_NAME="helm"
ACTION="${1:-all}"

log(){ printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

# ----- Fedora-only guard -----
fedora_guard(){
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    [[ "$ID" == "fedora" || "$ID_LIKE" == *"fedora"* || "$ID" == "rhel" ]] || die "Fedora/RHEL-only module."
  else
    die "Cannot detect OS."
  fi
}

# ----- Real user context (avoid writing into /root) -----
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
ZSH_COMP_DIR="$REAL_HOME/.zsh/completions"              # your fpath
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MODULE_CONF_SRC="$SCRIPT_DIR/config/helm.zsh"           # modules/fedora/config/helm.zsh
MODULE_CONF_DST="$REAL_HOME/.zsh/config/helm.zsh"
LOCAL_BIN="$REAL_HOME/.local/bin"

# ----- Normalize Architecture -----
normalize_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) echo "amd64" ;;
    aarch64) echo "arm64" ;;
    *)
      die "Unsupported architecture: $arch"
      ;;
  esac
}

install_deps(){
  log "Installing dependencies (sudo): curl tar gzip"
  sudo dnf makecache -y
  sudo dnf install -y curl tar gzip
}

install_helm(){
  log "Installing helm from GitHub releases"
  
  ARCH_NORM="$(normalize_arch)"
  HELM_VERSION="v3.15.0"  # You can make this configurable
  HELM_URL="https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH_NORM}.tar.gz"
  
  sudo -u "$REAL_USER" mkdir -p "$LOCAL_BIN"
  TMP_DIR="$(mktemp -d)"
  TMP_TAR="$(mktemp)"
  
  log "Downloading helm from $HELM_URL"
  curl -fsSL "$HELM_URL" -o "$TMP_TAR"
  
  sudo -u "$REAL_USER" tar -xzf "$TMP_TAR" -C "$TMP_DIR"
  sudo -u "$REAL_USER" mv "$TMP_DIR/linux-${ARCH_NORM}/helm" "$LOCAL_BIN/helm"
  sudo -u "$REAL_USER" chmod +x "$LOCAL_BIN/helm"
  
  rm -f "$TMP_TAR"
  rm -rf "$TMP_DIR"
  
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

  # Optional: copy module config if you keep one under modules/fedora/config/helm.zsh
  if [[ -f "$MODULE_CONF_SRC" ]]; then
    log "Installing Zsh config → $MODULE_CONF_DST"
    sudo -u "$REAL_USER" mkdir -p "$(dirname "$MODULE_CONF_DST")"
    install -m 0644 -o "$REAL_USER" -g "$REAL_USER" "$MODULE_CONF_SRC" "$MODULE_CONF_DST"
  else
    log "No module config found at $MODULE_CONF_SRC (skipping)."
  fi
}

clean_helm(){
  log "Removing helm"
  sudo -u "$REAL_USER" rm -f "$LOCAL_BIN/helm" || true

  log "Removing Zsh completion and config"
  sudo -u "$REAL_USER" rm -f "$ZSH_COMP_DIR/_helm" 2>/dev/null || true
  sudo -u "$REAL_USER" rm -f "$MODULE_CONF_DST" 2>/dev/null || true
  log "Clean complete."
}

# ----- Entry point -----
fedora_guard
case "$ACTION" in
  deps)    install_deps ;;
  install) install_deps; install_helm ;;
  config)  configure_helm ;;
  clean)   clean_helm ;;
  all)     install_deps; install_helm; configure_helm ;;
  *) echo "Usage: $0 [all|deps|install|config|clean]"; exit 1 ;;
esac

log "Done: $ACTION"

