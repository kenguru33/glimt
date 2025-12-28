#!/bin/bash
set -e
trap 'echo "❌ An error occurred in optional desktop setup." >&2' ERR

# === Parse flags and action ===
VERBOSE=false
ACTION=""
FLAGS=()

for arg in "$@"; do
  case "$arg" in
  --verbose)
    VERBOSE=true
    FLAGS+=("$arg")
    ;;
  --quiet)
    VERBOSE=false
    FLAGS+=("$arg")
    ;;
  all | install) ACTION="$arg" ;;
  *)
    echo "❌ Unknown argument: $arg"
    echo "Usage: $0 [--verbose|--quiet] [all|install]"
    exit 1
    ;;
  esac
done

ACTION="${ACTION:-all}"
GLIMT_ROOT="${GLIMT_ROOT:-$HOME/.glimt}"
STATE_FILE="$HOME/.config/glimt/optional-extras.selected"
mkdir -p "$(dirname "$STATE_FILE")"

# === OS Detection ===
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
  OS_ID="$ID"
  OS_ID_LIKE="${ID_LIKE:-}"
else
  echo "❌ Cannot detect OS. /etc/os-release missing."
  exit 1
fi

# Determine modules directory based on OS
if [[ "$OS_ID" == "fedora" || "$OS_ID_LIKE" == *"fedora"* || "$OS_ID" == "rhel" ]]; then
  MODULE_DIR="$GLIMT_ROOT/modules/fedora/extras"
elif [[ "$OS_ID" == "debian" || "$OS_ID_LIKE" == *"debian"* || "$OS_ID" == "ubuntu" ]]; then
  MODULE_DIR="$GLIMT_ROOT/modules/debian/extras"
else
  echo "❌ Unsupported OS: $OS_ID"
  exit 1
fi

# === Define modules: [name]=binary (or absolute path)
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
  ["virtualization-suite"]="/usr/bin/gnome-boxes"
  [notion]="notion"
  [ytmusic]="ytm"
  [outlook]="outlook"
  [teams]="teams"
  [chatgpt]="chatgpt"
)

# === Optional descriptions
declare -A MODULE_DESCRIPTIONS=(
  [zellij]="Zellij terminal multiplexer (like tmux)"
  ["1password-cli"]="1Password CLI tool (op)"
  ["jetbrains-toolbox"]="JetBrains Toolbox App for IDE management"
  [lens]="Lens Kubernetes IDE"
  [1password]="1Password Desktop GUI"
  [kitty]="Kitty GPU-accelerated terminal"
  [vscode]="Visual Studio Code"
  ["blackbox-terminal"]="BlackBox terminal"
  [discord]="Discord desktop client"
  [dotnet]=".NET SDK"
  [gitkraken]="GitKraken Git client"
  ["docker-rootless"]="Docker Rootless"
  [lazydocker]="LazyDocker terminal UI for Docker"
  [spotify]="Spotify desktop client"
  [pika]="Pika backup"
  [tableplus]="TablePlus database GUI"
  ["virtualization-suite"]="Full virtualization suite (GNOME Boxes + QEMU/KVM)"
  [notion]="Notion app (web app)"
  [ytmusic]="YouTube Music PWA"
  [outlook]="Outlook Web App"
  [teams]="Microsoft Teams PWA"
  [chatgpt]="ChatGPT PWA"
)

# --- Helper: check if module script likely needs sudo
needs_sudo() {
  local script="$1"
  [[ -x "$script" ]] || return 1
  grep -Eq \
    'apt|dnf|flatpak|snap|systemctl|/usr|/etc' \
    "$script"
}

# --- Flatpak detection
flatpak_app_installed() {
  command -v flatpak &>/dev/null || return 1
  flatpak info --user "$1" &>/dev/null && return 0
  flatpak info --system "$1" &>/dev/null && return 0
  return 1
}

# --- Detect installed modules
module_installed() {
  local name="$1"
  case "$name" in
  discord)
    flatpak_app_installed "com.discordapp.Discord" && return 0
    command -v discord &>/dev/null && return 0
    rpm -q discord &>/dev/null && return 0
    return 1
    ;;
  pika)
    flatpak_app_installed "org.gnome.World.PikaBackup"
    ;;
  spotify)
    flatpak_app_installed "com.spotify.Client"
    ;;
  tableplus)
    command -v tableplus &>/dev/null && return 0
    rpm -q tableplus &>/dev/null && return 0
    dpkg -s tableplus &>/dev/null && return 0
    return 1
    ;;
  dotnet)
    # Any installed SDK or runtime counts
    if command -v dotnet &>/dev/null; then
      dotnet --info &>/dev/null && return 0
    fi
    return 1
    ;;
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

# --- Spinner runner
run_with_spinner() {
  local title="$1"
  shift
  if command -v gum >/dev/null && [[ -t 1 && -t 2 ]]; then
    gum spin --spinner dot --title "$title" -- bash -c '"$@" >/dev/null 2>&1' _ "$@" || "$@"
  else
    echo "▶️  $title"
    "$@"
  fi
}

run_module_script() {
  local name="$1"
  local mode="$2"
  local script="$MODULE_DIR/install-$name.sh"

  [[ -x "$script" ]] || {
    echo "⚠️  Missing $script"
    return
  }

  if $VERBOSE; then
    bash "$script" "$mode" "${FLAGS[@]}"
  else
    run_with_spinner "Running $name…" bash "$script" "$mode" "${FLAGS[@]}"
  fi
}

main() {
  local menu=()
  local map=()
  local preselect=()

  for name in "${!MODULES[@]}"; do
    local label="$name"
    [[ -n "${MODULE_DESCRIPTIONS[$name]}" ]] && label="$name – ${MODULE_DESCRIPTIONS[$name]}"
    menu+=("$label")
    map+=("$label:$name")
    module_installed "$name" && preselect+=("$label")
  done

  local args=()
  for s in "${preselect[@]}"; do args+=(--selected "$s"); done

  IFS=$'\n' read -r -d '' -a selected < <(
    printf "%s\n" "${menu[@]}" | sort |
      gum choose --no-limit "${args[@]}" --height=15 && printf '\0'
  )

  declare -A WANT=()
  for sel in "${selected[@]}"; do
    for m in "${map[@]}"; do
      [[ "$m" == "$sel:"* ]] && WANT["${m#*:}"]=1
    done
  done

  for name in "${!MODULES[@]}"; do
    if [[ "${WANT[$name]}" == "1" ]]; then
      module_installed "$name" || run_module_script "$name" all
    else
      module_installed "$name" && run_module_script "$name" clean
    fi
  done

  printf "%s\n" "${!WANT[@]}" >"$STATE_FILE"
}

# === Entry point ===
case "$ACTION" in
all | install) main ;;
*)
  echo "Usage: $0 [--verbose|--quiet] [all|install]"
  exit 1
  ;;
esac
