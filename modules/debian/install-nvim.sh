#!/bin/bash
set -euo pipefail
trap 'echo "❌ Neovim setup failed. Exiting." >&2' ERR

MODULE_NAME="nvim"
ACTION="${1:-all}"
REAL_USER="${SUDO_USER:-$USER}"
HOME_DIR="$(eval echo "~$REAL_USER")"
CONFIG_DIR="$HOME_DIR/.zsh/config"
LOCAL_BIN="$HOME_DIR/.local/bin"
LOCAL_NVIM_DIR="$HOME_DIR/.local/share/nvim"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/config/nvim.zsh"
TARGET_FILE="$CONFIG_DIR/nvim.zsh"

# ---------------------------------------------------------
# Helpers
# ---------------------------------------------------------
log(){ printf "[%s] %s\n" "$MODULE_NAME" "$*" >&2; }
die(){ printf "ERROR: %s\n" "$*" >&2; exit 1; }

have_cmd(){ command -v "$1" >/dev/null 2>&1; }

normalize_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64) echo "linux-x86_64" ;;
    aarch64) echo "linux-arm64" ;;
    *)
      die "Unsupported architecture: $arch"
      ;;
  esac
}

testing_available() {
  # cheap check: if apt knows about a "testing" release, this will match
  apt-cache policy 2>/dev/null | grep -qE 'release .*a=testing|testing' || return 1
}

apt_update_ok() {
  sudo apt-get update -y >/dev/null
}

nvim_install_method="${NVIM_INSTALL_METHOD:-auto}" # auto|apt|tarball

nvim_version="${NVIM_VERSION:-stable}" # stable or a tag like v0.10.4

install_deps_apt() {
  # For APT installs we need apt itself (assumed) + sudo privileges.
  # Neovim package will come via apt.
  :
}

install_deps_tarball() {
  # Avoid apt-get update if tools are already present (APT can be broken due to 3rd party repos).
  local missing=()
  have_cmd curl || missing+=("curl")
  have_cmd tar || missing+=("tar")
  have_cmd gzip || missing+=("gzip")

  if [[ "${#missing[@]}" -eq 0 ]]; then
    return 0
  fi

  log "Installing dependencies (sudo): ${missing[*]}"
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends "${missing[@]}"
}

install_nvim_apt_testing() {
  if ! testing_available; then
    log "Debian testing repository not available (cherry-pick missing)."
    log "Hint: run /home/bernt/.glimt/modules/debian/install-extra-packages-sources.sh cherry-pick"
    return 1
  fi

  log "📦 Installing Neovim from Debian testing (cherry-pick)..."
  sudo apt-get update -y
  sudo apt-get install -y -t testing neovim
  log "✅ Neovim installed from testing"
}

install_nvim_tarball() {
  install_deps_tarball

  local arch_norm url tmp_tar tmp_dir extracted_dir
  arch_norm="$(normalize_arch)"

  if [[ "$nvim_version" == "stable" ]]; then
    url="https://github.com/neovim/neovim/releases/latest/download/nvim-${arch_norm}.tar.gz"
  else
    url="https://github.com/neovim/neovim/releases/download/${nvim_version}/nvim-${arch_norm}.tar.gz"
  fi

  log "📦 Installing Neovim from official tarball into $LOCAL_BIN"

  sudo -u "$REAL_USER" mkdir -p "$LOCAL_BIN" "$LOCAL_NVIM_DIR"
  tmp_tar="$(sudo -u "$REAL_USER" mktemp)"
  tmp_dir="$(sudo -u "$REAL_USER" mktemp -d)"

  log "Downloading: $url"
  sudo -u "$REAL_USER" curl -fsSL "$url" -o "$tmp_tar"
  sudo -u "$REAL_USER" tar -xzf "$tmp_tar" -C "$tmp_dir"

  # Tarball contains a single top-level dir like nvim-linux64/
  extracted_dir="$(find "$tmp_dir" -maxdepth 1 -type d -name 'nvim-*' | head -n1)"
  [[ -n "$extracted_dir" ]] || die "Unexpected Neovim tarball layout."

  # Install into a versioned directory and repoint "current"
  sudo -u "$REAL_USER" rm -rf "$LOCAL_NVIM_DIR/${arch_norm}-${nvim_version}" 2>/dev/null || true
  sudo -u "$REAL_USER" mv "$extracted_dir" "$LOCAL_NVIM_DIR/${arch_norm}-${nvim_version}"
  sudo -u "$REAL_USER" ln -sfn "$LOCAL_NVIM_DIR/${arch_norm}-${nvim_version}" "$LOCAL_NVIM_DIR/current"
  sudo -u "$REAL_USER" ln -sfn "$LOCAL_NVIM_DIR/current/bin/nvim" "$LOCAL_BIN/nvim"

  sudo -u "$REAL_USER" rm -f "$tmp_tar"
  sudo -u "$REAL_USER" rm -rf "$tmp_dir"

  log "✅ Neovim installed: $("$LOCAL_BIN/nvim" --version | head -n1 2>/dev/null || echo nvim)"
  if ! sudo -u "$REAL_USER" bash -lc "command -v nvim >/dev/null 2>&1"; then
    log "Note: nvim installed to $LOCAL_BIN/nvim but ~/.local/bin may not be in your PATH."
  fi
}

# ---------------------------------------------------------
# deps
# ---------------------------------------------------------
deps() {
  case "$nvim_install_method" in
    apt)
      install_deps_apt
      install_nvim_apt_testing
      ;;
    tarball)
      install_nvim_tarball
      ;;
    auto)
      # Prefer apt if it looks viable; otherwise fall back (especially useful when APT is broken).
      if testing_available && apt_update_ok; then
        install_nvim_apt_testing || install_nvim_tarball
      else
        install_nvim_tarball
      fi
      ;;
    *)
      die "Unknown NVIM_INSTALL_METHOD='$nvim_install_method' (expected: apt|tarball|auto)"
      ;;
  esac
}

# ---------------------------------------------------------
# install
# ---------------------------------------------------------
install() {
  echo "ℹ️ Neovim installed. Nothing else to install."
}

# ---------------------------------------------------------
# config
# ---------------------------------------------------------
config() {
  echo "📝 Installing nvim.zsh config from template..."

  mkdir -p "$CONFIG_DIR"
  cp "$TEMPLATE_FILE" "$TARGET_FILE"
  chown "$REAL_USER:$REAL_USER" "$TARGET_FILE"

  echo "✅ Installed $TARGET_FILE"
}

# ---------------------------------------------------------
# clean
# ---------------------------------------------------------
clean() {
  echo "🧹 Removing Neovim config..."

  rm -f "$TARGET_FILE"
  echo "✅ Removed $TARGET_FILE"

  echo "ℹ️ Neovim itself not removed automatically."
  echo "   - If installed via tarball: remove $LOCAL_BIN/nvim and $LOCAL_NVIM_DIR"
}

# ---------------------------------------------------------
# entrypoint
# ---------------------------------------------------------
case "$ACTION" in
all)
  deps
  install
  config
  ;;
deps) deps ;;
install) install ;;
config) config ;;
clean) clean ;;
*)
  echo "❌ Unknown action: $ACTION"
  echo "Usage: $0 [all|deps|install|config|clean]"
  exit 1
  ;;
esac
