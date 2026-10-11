#!/usr/bin/env bash
# Glimt module: Install Kubernetes Helm (GitHub releases) on Fedora.
# Actions: all | deps | install | config | clean

set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="helm"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

GLIMT_VERSIONS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../versions.env"
# shellcheck source=../../versions.env
source "$GLIMT_VERSIONS"

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
ZSH_COMP_DIR="$HOME_DIR/.zsh/completions"              # your fpath
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
MODULE_CONF_SRC="$SCRIPT_DIR/config/helm.zsh"           # modules/fedora/config/helm.zsh
MODULE_CONF_DST="$HOME_DIR/.zsh/config/helm.zsh"
LOCAL_BIN="$HOME_DIR/.local/bin"

install_deps(){
  log "Installing dependencies (sudo): curl tar gzip"
  dnf_ensure curl tar gzip
}

install_helm(){
  local current
  current="$("$LOCAL_BIN/helm" version --template '{{.Version}}' 2>/dev/null || true)"
  if [[ "$current" == "$HELM_VERSION" ]]; then
    log "helm $HELM_VERSION is up to date"
    return
  fi

  log "Installing helm $HELM_VERSION from GitHub releases${current:+ (replacing $current)}"
  
  ARCH_NORM="$(normalize_arch)"
  HELM_URL="https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH_NORM}.tar.gz"
  
  run_as_user mkdir -p "$LOCAL_BIN"

  # Download and extract as the caller (the temp dir is only readable by
  # them), then install the binary owned by the real user.
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  log "Downloading helm from $HELM_URL"
  if ! curl -fsSL "$HELM_URL" -o "$tmp_dir/helm.tar.gz" ||
     ! tar -xzf "$tmp_dir/helm.tar.gz" -C "$tmp_dir"; then
    rm -rf "$tmp_dir"
    die "Failed to download/extract $HELM_URL"
  fi

  sudo install -o "$REAL_USER" -g "$REAL_USER" -m 0755 \
    "$tmp_dir/linux-${ARCH_NORM}/helm" "$LOCAL_BIN/helm"
  rm -rf "$tmp_dir"

  verify_binary "$LOCAL_BIN/helm" version --short
}

configure_helm(){
  if [[ ! -x "$LOCAL_BIN/helm" ]]; then
    log "helm not found at $LOCAL_BIN/helm; skipping completions."
    return 0
  fi

  log "Generating Zsh completion → $ZSH_COMP_DIR/_helm"
  run_as_user mkdir -p "$ZSH_COMP_DIR"
  # Generate completion as the real user to avoid root-owned files
  if run_as_user sh -c '"$1" completion zsh > "$2"' _ "$LOCAL_BIN/helm" "$ZSH_COMP_DIR/_helm"; then
    run_as_user chmod 644 "$ZSH_COMP_DIR/_helm" || true
    log "Completions written: $ZSH_COMP_DIR/_helm"
  else
    die "Failed to generate Helm Zsh completion"
  fi

  # Optional: copy module config if you keep one under modules/fedora/config/helm.zsh
  if [[ -f "$MODULE_CONF_SRC" ]]; then
    log "Installing Zsh config → $MODULE_CONF_DST"
    deploy_config "$MODULE_CONF_SRC" "$MODULE_CONF_DST"
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
  install) install_helm ;;
  config)  configure_helm ;;
  clean)   clean_helm ;;
  all)     install_deps; install_helm; configure_helm ;;
  *) echo "Usage: $0 [all|deps|install|config|clean]"; exit 1 ;;
esac

log "Done: $ACTION"


