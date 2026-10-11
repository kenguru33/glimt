#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[$MODULE_NAME] error on line $LINENO" >&2' ERR

MODULE_NAME="k9s"
ACTION="${1:-all}"

GLIMT_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=lib.sh
source "$GLIMT_LIB"

GLIMT_VERSIONS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../versions.env"
# shellcheck source=../../versions.env
source "$GLIMT_VERSIONS"

CONFIG_TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config"
TARGET_CONFIG_DIR="$HOME_DIR/.zsh/config"
TARGET_CONFIG_FILE="$TARGET_CONFIG_DIR/k9s.zsh"
K9S_CONFIG_DIR="$HOME_DIR/.config/k9s"
SKIN_DIR="$K9S_CONFIG_DIR/skins"
SKIN_FILE="catppuccin-mocha.yaml"
K9S_CONFIG_TEMPLATE="$CONFIG_TEMPLATE_DIR/k9s-config.yaml"
# Older versions of this module appended exactly this line to ~/.zshrc. The
# zshrc template (install-zsh.sh) already puts ~/.local/bin on PATH.
# shellcheck disable=SC2016  # literal line, not expanded
LEGACY_PATH_LINE='export PATH="$HOME/.local/bin:$PATH"'

# === OS Check (Fedora only) ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  echo "Error: Cannot detect OS. /etc/os-release missing."
  exit 1
fi

if [[ "$ID" != "fedora" && "$ID_LIKE" != *"fedora"* && "$ID" != "rhel" ]]; then
  echo "Error: This module supports Fedora/RHEL-based systems only."
  exit 1
fi

# === Step: deps ===
install_dependencies() {
  echo "Installing dependencies..."
  dnf_ensure curl tar gzip
}

# === Step: install ===
install_k9s() {
  # `k9s version -s` prints "Version  v0.32.4" among other lines
  local current
  current="$("$HOME_DIR/.local/bin/k9s" version -s 2>/dev/null | awk '$1 == "Version" {print $2}' || true)"
  if [[ "$current" == "$K9S_VERSION" ]]; then
    echo "k9s $K9S_VERSION is up to date"
    return
  fi

  echo "Installing K9s $K9S_VERSION to ~/.local/bin..."

  local norm_arch url
  norm_arch="$(normalize_arch)"
  url="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_${norm_arch}.tar.gz"

  run_as_user mkdir -p "$HOME_DIR/.local/bin"

  # Download and extract as the caller (the temp dir is only readable by
  # them), then install the binary owned by the real user.
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  if ! curl -fsSL "$url" -o "$tmp_dir/k9s.tar.gz" ||
     ! tar -xzf "$tmp_dir/k9s.tar.gz" -C "$tmp_dir"; then
    rm -rf "$tmp_dir"
    die "Failed to download/extract $url"
  fi
  sudo install -o "$REAL_USER" -g "$REAL_USER" -m 0755 "$tmp_dir/k9s" "$HOME_DIR/.local/bin/k9s"
  rm -rf "$tmp_dir"

  echo "K9s installed at ~/.local/bin/k9s"
  verify_binary "$HOME_DIR/.local/bin/k9s" version
}

# === Step: config ===
config_k9s() {
  echo "Installing K9s config and theme..."

  if [[ ! -x "$HOME_DIR/.local/bin/k9s" ]]; then
    die "K9s binary not found. Run 'install' first."
  fi

  # Shell completion loader config
  if [[ -f "$CONFIG_TEMPLATE_DIR/k9s.zsh" ]]; then
    deploy_config "$CONFIG_TEMPLATE_DIR/k9s.zsh" "$TARGET_CONFIG_FILE"
    echo "Installed Zsh completion config: $TARGET_CONFIG_FILE"
  fi

  # Bash/fish completions — the redirect runs in the user's shell so the
  # files are user-owned (a redirect in this shell would run as root)
  run_as_user mkdir -p "$HOME_DIR/.local/share/bash-completion/completions" "$HOME_DIR/.config/fish/completions"
  run_as_user sh -c '"$1" completion bash > "$2"' _ \
    "$HOME_DIR/.local/bin/k9s" "$HOME_DIR/.local/share/bash-completion/completions/k9s" || true
  run_as_user sh -c '"$1" completion fish > "$2"' _ \
    "$HOME_DIR/.local/bin/k9s" "$HOME_DIR/.config/fish/completions/k9s.fish" || true

  # Catppuccin theme
  run_as_user mkdir -p "$SKIN_DIR"
  run_as_user curl -fsSL "https://raw.githubusercontent.com/catppuccin/k9s/main/dist/$SKIN_FILE" \
    -o "$SKIN_DIR/$SKIN_FILE"
  echo "Theme saved to $SKIN_DIR/$SKIN_FILE"

  # config.yaml (an existing one is backed up by deploy_config)
  deploy_config "$K9S_CONFIG_TEMPLATE" "$K9S_CONFIG_DIR/config.yaml"
  echo "config.yaml set to Catppuccin Mocha"
}

# === Step: clean ===
clean_k9s() {
  echo "Removing K9s and related files..."

  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.local/bin/k9s"
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.local/share/bash-completion/completions/k9s"
  sudo -u "$REAL_USER" rm -f "$HOME_DIR/.config/fish/completions/k9s.fish"
  sudo -u "$REAL_USER" rm -f "$TARGET_CONFIG_FILE"

  # ~/.config/k9s: only what config_k9s deployed — keep other skins, plugins,
  # aliases, clusters, etc.
  run_as_user rm -f "${SKIN_DIR:?}/${SKIN_FILE:?}"
  # config.yaml: remove only while it is still glimt's template; a copy the
  # user has edited since is left in place
  if [[ -f "$K9S_CONFIG_DIR/config.yaml" ]]; then
    if cmp -s "$K9S_CONFIG_TEMPLATE" "$K9S_CONFIG_DIR/config.yaml"; then
      run_as_user rm -f "${K9S_CONFIG_DIR:?}/config.yaml"
    else
      warn "Keeping $K9S_CONFIG_DIR/config.yaml (modified since glimt deployed it)"
    fi
  fi
  # Drop the directories only if nothing else lives there
  run_as_user rmdir "$SKIN_DIR" 2>/dev/null || true
  run_as_user rmdir "$K9S_CONFIG_DIR" 2>/dev/null || true

  # Legacy: older versions appended the PATH line at the end of ~/.zshrc. Only
  # an exact match on the *last* line is removed — the zshrc template carries
  # the same line near the top and that one must stay.
  if [[ -f "$HOME_DIR/.zshrc" && "$(tail -n 1 "$HOME_DIR/.zshrc")" == "$LEGACY_PATH_LINE" ]]; then
    run_as_user sed -i '$d' "$HOME_DIR/.zshrc"
    echo "Removed legacy PATH line appended to ~/.zshrc"
  fi

  echo "All K9s files removed."
}

# === Entry Point ===
case "$ACTION" in
  deps)    install_dependencies ;;
  install) install_k9s ;;
  config)  config_k9s ;;
  clean)   clean_k9s ;;
  all)     install_dependencies; install_k9s; config_k9s ;;
  *)
    echo "[$MODULE_NAME] unknown action: $ACTION" >&2
    echo "Usage: $0 [all|deps|install|config|clean]"
    exit 1
    ;;
esac


