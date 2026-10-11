#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Optional extras setup failed." >&2' ERR

export PATH="$HOME/.dotnet:$PATH"

# -----------------------------
# Args
# -----------------------------
VERBOSE=false
ACTION="all"

for arg in "$@"; do
  case "$arg" in
  -v | --verbose) VERBOSE=true ;;
  --quiet) VERBOSE=false ;;
  all | install) ACTION="$arg" ;;
  *)
    echo "❌ Unknown argument: $arg"
    exit 1
    ;;
  esac
done

# -----------------------------
# Paths
# -----------------------------
GLIMT_ROOT="${GLIMT_ROOT:-$HOME/.glimt}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup-lib.sh"
STATE_FILE="$HOME/.config/glimt/optional-extras.selected"
mkdir -p "$(dirname "$STATE_FILE")"

# -----------------------------
# OS detection (SAFE)
# -----------------------------
. /etc/os-release
ID_LIKE="${ID_LIKE:-}"

if [[ "$ID" != "fedora" && "$ID_LIKE" != *fedora* && "$ID" != "rhel" ]]; then
  echo "❌ Unsupported OS: $ID. Glimt requires Fedora or RHEL."
  exit 1
fi

MODULE_DIR="$GLIMT_ROOT/modules/fedora/extras"

# -----------------------------
# MODULES
# -----------------------------
declare -A MODULES=(
  [zellij]="zellij"
  ["1password-cli"]="op"
  ["jetbrains-toolbox"]="jetbrains-toolbox"
  [lens]="/opt/Lens/lens-desktop"
  [1password]="1password"
  [vscode]="code"
  [discord]="/usr/share/discord/Discord"
  [dotnet]="dotnet"
  [gitkraken]="gitkraken"
  ["docker-rootless"]="dockerd-rootless.sh"
  [lazydocker]="lazydocker"
  [spotify]="spotify"
  [pika]="pika"
  [tableplus]="tableplus"
  [notion]="notion"
  [ytmusic]="ytm"
  [outlook]="outlook"
  [teams]="teams"
  [chatgpt]="chatgpt"
  ["claude-code"]="claude"
  [powershell]="pwsh"
)

declare -A MODULE_DESCRIPTIONS=(
  [zellij]="Zellij terminal multiplexer"
  ["1password-cli"]="1Password CLI"
  ["jetbrains-toolbox"]="JetBrains Toolbox"
  [lens]="Lens Kubernetes IDE"
  [1password]="1Password GUI"
  [vscode]="Visual Studio Code"
  [discord]="Discord"
  [dotnet]=".NET SDK / Runtime"
  [gitkraken]="GitKraken"
  ["docker-rootless"]="Docker Rootless"
  [lazydocker]="LazyDocker"
  [spotify]="Spotify"
  [pika]="Pika Backup"
  [tableplus]="TablePlus"
  [notion]="Notion"
  [ytmusic]="YouTube Music"
  [outlook]="Outlook PWA"
  [teams]="Teams PWA"
  [chatgpt]="ChatGPT PWA"
  ["claude-code"]="Claude Code CLI"
  [powershell]="PowerShell 7 (pwsh)"
)

# -----------------------------
# Detection (UX only)
# -----------------------------
flatpak_app_installed() {
  command -v flatpak &>/dev/null || return 1
  flatpak info --user "$1" &>/dev/null && return 0
  flatpak info --system "$1" &>/dev/null && return 0
  return 1
}

module_installed() {
  local name="$1"
  case "$name" in
  discord) flatpak_app_installed "com.discordapp.Discord" ;;
  spotify) flatpak_app_installed "com.spotify.Client" ;;
  pika) flatpak_app_installed "org.gnome.World.PikaBackup" ;;
  *)
    local bin="${MODULES[$name]}"
    if [[ "$bin" == /* ]]; then
      [[ -x "$bin" ]]
    else
      command -v "$bin" &>/dev/null
    fi
    ;;
  esac
}

# -----------------------------
# Run module (progress bar by default, full output with --verbose)
# -----------------------------
run_module() {
  local name="$1"
  local mode="$2"
  local script="$MODULE_DIR/install-$name.sh"

  if [[ ! -x "$script" ]]; then
    echo "⚠️ Missing $script"
    return
  fi

  if [[ "$mode" == "clean" ]]; then
    progress_run "Removing $name" bash "$script" clean
  else
    progress_run "Installing $name" bash "$script" all
  fi
}

# -----------------------------
# Main
# -----------------------------
main() {
  if ! command -v gum >/dev/null 2>&1; then
    echo "❌ gum is required for the extras picker (sudo dnf install -y gum)." >&2
    exit 1
  fi

  declare -A PREV=()
  if [[ -f "$STATE_FILE" ]]; then
    while read -r m; do
      [[ -n "$m" ]] && PREV["$m"]=1
    done <"$STATE_FILE"
  fi

  menu=()
  map=()
  preselect=()

  for m in "${!MODULES[@]}"; do
    if [[ "${PREV[$m]:-}" != "1" ]] && module_installed "$m"; then
      label="$m – ${MODULE_DESCRIPTIONS[$m]} [not managed by glimt]"
    else
      label="$m – ${MODULE_DESCRIPTIONS[$m]}"
    fi
    menu+=("$label")
    map+=("$label:$m")

    if [[ "${PREV[$m]:-}" == "1" ]] || module_installed "$m"; then
      preselect+=(--selected "$label")
    fi
  done

  IFS=$'\n' read -r -d '' -a selected < <(
    printf "%s\n" "${menu[@]}" | sort |
      gum choose --no-limit --height=15 "${preselect[@]}" && printf '\0'
  )

  declare -A WANT=()
  for s in "${selected[@]}"; do
    for m in "${map[@]}"; do
      [[ "$m" == "$s:"* ]] && WANT["${m#*:}"]=1
    done
  done

  # Work out what changes first, so the progress bar knows the total
  PLAN=()
  for m in "${!MODULES[@]}"; do
    now="${WANT[$m]:-}"
    before="${PREV[$m]:-}"

    if [[ "$now" == "1" && "$before" != "1" ]]; then
      PLAN+=("all:$m")
    elif [[ "$now" != "1" ]] && { [[ "$before" == "1" ]] || module_installed "$m"; }; then
      PLAN+=("clean:$m")
    fi
  done

  if (( ${#PLAN[@]} > 0 )); then
    glimt_require_sudo
    progress_init "${#PLAN[@]}"
    for step in "${PLAN[@]}"; do
      run_module "${step#*:}" "${step%%:*}"
    done
    progress_finish
  fi

  printf "%s\n" "${!WANT[@]}" >"$STATE_FILE"
}

main
