#!/bin/bash
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
  --verbose) VERBOSE=true ;;
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
STATE_FILE="$HOME/.config/glimt/optional-extras.selected"
mkdir -p "$(dirname "$STATE_FILE")"

# -----------------------------
# OS detection (SAFE)
# -----------------------------
. /etc/os-release
ID_LIKE="${ID_LIKE:-}"

IS_FEDORA=false
IS_DEBIAN=false

if [[ "$ID" == "fedora" || "$ID_LIKE" == *fedora* || "$ID" == "rhel" ]]; then
  IS_FEDORA=true
elif [[ "$ID" == "debian" || "$ID_LIKE" == *debian* || "$ID" == "ubuntu" ]]; then
  IS_DEBIAN=true
else
  echo "❌ Unsupported OS: $ID"
  exit 1
fi

if $IS_FEDORA; then
  MODULE_DIR="$GLIMT_ROOT/modules/fedora/extras"
else
  MODULE_DIR="$GLIMT_ROOT/modules/debian/extras"
fi

# -----------------------------
# MODULES
# -----------------------------
declare -A MODULES=(
  [zellij]="zellij"
  ["1password-cli"]="op"
  ["jetbrains-toolbox"]="jetbrains-toolbox"
  [lens]="/opt/Lens/lens-desktop"
  [1password]="1password"
  [kitty]="kitty"
  [vscode]="code"
  ["blackbox-terminal"]="blackbox-terminal"
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
)

declare -A MODULE_DESCRIPTIONS=(
  [zellij]="Zellij terminal multiplexer"
  ["1password-cli"]="1Password CLI"
  ["jetbrains-toolbox"]="JetBrains Toolbox"
  [lens]="Lens Kubernetes IDE"
  [1password]="1Password GUI"
  [kitty]="Kitty terminal"
  [vscode]="Visual Studio Code"
  ["blackbox-terminal"]="BlackBox terminal"
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
)

# -----------------------------
# Debian-only module
# -----------------------------
if $IS_DEBIAN; then
  MODULES["virtualization-suite"]="/usr/bin/gnome-boxes"
  MODULE_DESCRIPTIONS["virtualization-suite"]="GNOME Boxes + KVM"
fi

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
# Spinner (INSTALL ONLY)
# -----------------------------
run_with_spinner() {
  local title="$1"
  shift
  if command -v gum &>/dev/null && [[ -t 1 && -t 2 ]]; then
    gum spin --spinner dot --title "$title" -- bash -c '"$@" >/dev/null 2>&1' _ "$@" || "$@"
  else
    echo "▶️  $title"
    "$@"
  fi
}

# -----------------------------
# Run module
# -----------------------------
run_module() {
  local name="$1"
  local mode="$2"
  local script="$MODULE_DIR/install-$name.sh"

  [[ -x "$script" ]] || {
    echo "⚠️ Missing $script"
    return
  }

  if [[ "$mode" == "clean" ]]; then
    echo "🧹 Cleaning $name…"
    bash "$script" clean >/dev/null
    echo "✔️ install-$name.sh cleaned"
    return
  fi

  if $VERBOSE; then
    echo "▶️ Running install-$name.sh"
    bash "$script" all
    echo "✔️ install-$name.sh finished"
  else
    run_with_spinner "Running $name…" bash "$script" all
    gum style --foreground 10 "✔️ install-$name.sh finished"
  fi
}

# -----------------------------
# Main
# -----------------------------
main() {
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
    label="$m – ${MODULE_DESCRIPTIONS[$m]}"
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

  for m in "${!MODULES[@]}"; do
    now="${WANT[$m]:-}"
    before="${PREV[$m]:-}"

    if [[ "$now" == "1" && "$before" != "1" ]]; then
      run_module "$m" all
    elif [[ "$now" != "1" && "$before" == "1" ]]; then
      run_module "$m" clean
    fi
  done

  printf "%s\n" "${!WANT[@]}" >"$STATE_FILE"
}

main
