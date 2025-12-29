#!/usr/bin/env bash
# Glimt module: Install Kubernetes Helm (APT repo) on Debian.
# Actions: all | deps | install | config | clean

set -Eeuo pipefail

MODULE_NAME="helm"
ACTION="${1:-all}"

log(){ printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

have_cmd(){ command -v "$1" >/dev/null 2>&1; }
have_pkg(){ dpkg -s "$1" >/dev/null 2>&1; }

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
LOCAL_BIN="$REAL_HOME/.local/bin"

# Install method:
# - apt: use Helm's APT repository (baltocdn)
# - tarball: download from get.helm.sh and install into ~/.local/bin
# - auto (default): try apt first; fall back to tarball if repo is unreachable
HELM_INSTALL_METHOD="${HELM_INSTALL_METHOD:-auto}"
HELM_VERSION="${HELM_VERSION:-v3.15.0}"

# ----- Helm APT repo -----
KEY_URL="https://baltocdn.com/helm/signing.asc"
KEYRING_DIR="/etc/apt/keyrings"
KEYRING_FILE="$KEYRING_DIR/helm.gpg"
LIST_FILE="/etc/apt/sources.list.d/helm-stable-debian.list"
APT_ARCH="$(dpkg --print-architecture)"
APT_LINE="deb [arch=${APT_ARCH} signed-by=${KEYRING_FILE}] https://baltocdn.com/helm/stable/debian/ all main"

install_deps(){
  # Important: user machines sometimes have a broken third-party APT repo that makes
  # `apt-get update` fail (e.g. missing Release file). We should not fail Helm
  # installation if required tools are already present.
  local need_any=0
  local missing=()

  # For APT method we need gpg + ca-certs to add the repo; for tarball we need tar/gzip.
  # `apt-transport-https` is obsolete on modern Debian (HTTPS is built-in), so we avoid
  # requiring it to reduce unnecessary apt traffic.
  have_cmd curl || { missing+=("curl"); need_any=1; }
  have_pkg ca-certificates || { missing+=("ca-certificates"); need_any=1; }

  case "${HELM_INSTALL_METHOD}" in
    apt)
      have_cmd gpg || { missing+=("gpg"); need_any=1; }
      ;;
    tarball)
      have_cmd tar || { missing+=("tar"); need_any=1; }
      have_cmd gzip || { missing+=("gzip"); need_any=1; }
      ;;
    auto)
      have_cmd gpg || { missing+=("gpg"); need_any=1; }
      have_cmd tar || { missing+=("tar"); need_any=1; }
      have_cmd gzip || { missing+=("gzip"); need_any=1; }
      ;;
    *)
      die "Unknown HELM_INSTALL_METHOD='$HELM_INSTALL_METHOD' (expected: apt|tarball|auto)"
      ;;
  esac

  if [[ "$need_any" -eq 0 ]]; then
    log "Dependencies already present; skipping apt-get."
    return 0
  fi

  log "Installing dependencies (sudo): ${missing[*]}"
  if ! sudo apt-get update -y; then
    cat >&2 <<'EOF'
ERROR: apt-get update failed.
This is usually caused by a broken third-party APT repository (e.g. 404 / missing Release file).

Fix it by disabling/removing the failing repo, then re-run this installer.
To locate the repo definition:
  sudo grep -R "deb\\.tableplus\\.com\\|tableplus\\|baltocdn\\.com" /etc/apt/sources.list /etc/apt/sources.list.d/*.list
EOF
    return 1
  fi

  # Note: apt package names differ slightly from command names in some cases.
  # `gpg` is provided by package `gpg` (and/or gnupg); `tar` and `gzip` match.
  sudo apt-get install -y --no-install-recommends "${missing[@]}"
}

setup_repo(){
  log "Configuring Helm APT repository"
  sudo install -d -m 0755 "$KEYRING_DIR"
  if ! curl -fsSL "$KEY_URL" | sudo gpg --dearmor --yes -o "$KEYRING_FILE"; then
    sudo rm -f "$KEYRING_FILE" 2>/dev/null || true
    log "Failed to fetch/import Helm APT key from: $KEY_URL"
    log "This is commonly a DNS issue resolving 'baltocdn.com'."
    return 1
  fi
  sudo chmod 0644 "$KEYRING_FILE"
  echo "$APT_LINE" | sudo tee "$LIST_FILE" >/dev/null
  sudo chmod 0644 "$LIST_FILE"
}

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

helm_bin() {
  command -v helm 2>/dev/null || true
}

install_helm_apt(){
  setup_repo || return 1
  log "Installing helm (APT)"
  sudo apt-get update -y || return 1
  sudo apt-get install -y helm || return 1
  log "Installed: $(helm version --short 2>/dev/null || echo 'helm')"
}

install_helm_tarball(){
  log "Installing helm from official tarball (get.helm.sh) into $LOCAL_BIN"

  local arch_norm tmp_dir tmp_tar helm_url
  arch_norm="$(normalize_arch)"
  helm_url="https://get.helm.sh/helm-${HELM_VERSION}-linux-${arch_norm}.tar.gz"

  sudo -u "$REAL_USER" mkdir -p "$LOCAL_BIN"

  # Create temp paths as the real user so this works even when the module is run via sudo.
  tmp_dir="$(sudo -u "$REAL_USER" mktemp -d)"
  tmp_tar="$(sudo -u "$REAL_USER" mktemp)"

  log "Downloading: $helm_url"
  sudo -u "$REAL_USER" curl -fsSL "$helm_url" -o "$tmp_tar"

  sudo -u "$REAL_USER" tar -xzf "$tmp_tar" -C "$tmp_dir"
  sudo -u "$REAL_USER" mv "$tmp_dir/linux-${arch_norm}/helm" "$LOCAL_BIN/helm"
  sudo -u "$REAL_USER" chmod +x "$LOCAL_BIN/helm"

  sudo -u "$REAL_USER" rm -f "$tmp_tar"
  sudo -u "$REAL_USER" rm -rf "$tmp_dir"

  log "Installed: $("$LOCAL_BIN/helm" version --short 2>/dev/null || echo 'helm')"
  if ! sudo -u "$REAL_USER" bash -lc "command -v helm >/dev/null 2>&1"; then
    log "Note: helm was installed to $LOCAL_BIN/helm but ~/.local/bin may not be in your PATH."
  fi
}

install_helm(){
  case "$HELM_INSTALL_METHOD" in
    apt)
      install_helm_apt
      ;;
    tarball)
      install_helm_tarball
      ;;
    auto)
      if install_helm_apt; then
        :
      else
        log "APT install failed; falling back to tarball install."
        install_helm_tarball
      fi
      ;;
    *)
      die "Unknown HELM_INSTALL_METHOD='$HELM_INSTALL_METHOD' (expected: apt|tarball|auto)"
      ;;
  esac
}

configure_helm(){
  local hb
  hb="$(helm_bin)"
  if [[ -z "$hb" && -x "$LOCAL_BIN/helm" ]]; then
    hb="$LOCAL_BIN/helm"
  fi
  if [[ -z "$hb" ]]; then
    log "helm not found; skipping completions."
    return 0
  fi

  log "Generating Zsh completion → $ZSH_COMP_DIR/_helm"
  sudo -u "$REAL_USER" mkdir -p "$ZSH_COMP_DIR"
  # Generate completion as the real user to avoid root-owned files
  if sudo -u "$REAL_USER" bash -lc "'$hb' completion zsh > '$ZSH_COMP_DIR/_helm'"; then
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
  # Also remove local install (tarball method)
  sudo -u "$REAL_USER" rm -f "$LOCAL_BIN/helm" 2>/dev/null || true

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
