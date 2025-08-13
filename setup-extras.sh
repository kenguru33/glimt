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
MODULE_DIR="$GLIMT_ROOT/modules/debian/extras"
STATE_FILE="$HOME/.config/glimt/optional-extras.selected"
mkdir -p "$(dirname "$STATE_FILE")"

# === Define modules: [name]=binary (or absolute path)
declare -A MODULES=(
  [zellij]="zellij"
  [1password - cli]="op"
  [chrome]="google-chrome"
  [jetbrains - toolbox]="jetbrains-toolbox"
  [lens]="/opt/Lens/lens-desktop"
  [1password]="1password"
  [kitty]="kitty"
  [vscode]="code"
  [discord]="/usr/share/discord/Discord"
  # .NET versions share the same 'dotnet' host binary
  [dotnet8]="dotnet"
  [dotnet9]="dotnet"
  [gitkraken]="gitkraken"
)

# === Optional descriptions
declare -A MODULE_DESCRIPTIONS=(
  [zellij]="Zellij terminal multiplexer (like tmux)"
  [1password - cli]="1Password CLI tool (op)"
  [chrome]="Google Chrome browser"
  [jetbrains - toolbox]="JetBrains Toolbox App for IDE management"
  [lens]="Lens Kubernetes IDE"
  [1password]="1Password Desktop GUI"
  [kitty]="Kitty GPU-accelerated terminal"
  [vscode]="Visual Studio Code"
  [discord]="Discord desktop client"
  [1password - cli]="1Password CLI tool (op)"
  [dotnet8]=".NET 8 SDK + runtime"
  [dotnet9]=".NET 9 SDK + runtime"
  [gitkraken]="GitKraken Git client"
)

# --- Helper: check if module script likely needs sudo (heuristic; unchanged)
needs_sudo() {
  local script="$1"
  local mode="${2:-all}"
  [[ -x "$script" ]] || return 1

  # Heuristic search for privileged commands
  grep -Eq \
    '(^|[^[:alnum:]_])(apt(-get)?[[:space:]]+(install|remove|purge)|dpkg[[:space:]]+-i|flatpak[[:space:]]+(install|uninstall)|snap[[:space:]]+(install|remove)|systemctl[[:space:]]+(enable|disable|start|stop)|update-alternatives|(^|[[:space:]])cp[[:space:]]+.*\s/(usr|etc)/|(^|[[:space:]])install[[:space:]]+.*\s/(usr|etc)/)' \
    "$script"
}

# --- Helper: determine if a module is actually installed right now
module_installed() {
  local name="$1"
  case "$name" in
  dotnet8)
    dotnet --list-sdks 2>/dev/null | grep -q '^8\.'
    ;;
  dotnet9)
    dotnet --list-sdks 2>/dev/null | grep -q '^9\.'
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

run_module_script() {
  local name="$1"
  local mode="$2"
  local script="$MODULE_DIR/install-$name.sh"
  local label="install-$name.sh"
  [[ "$mode" == "clean" ]] && label="$label ($mode)"

  if [[ ! -x "$script" ]]; then
    echo "⚠️  Missing or non-executable: $script"
    return
  fi

  if $VERBOSE; then
    echo "▶️  Running: $label"
    [[ -n "${MODULE_DESCRIPTIONS[$name]}" ]] && echo "ℹ️  ${MODULE_DESCRIPTIONS[$name]}"
    bash "$script" "$mode" "${FLAGS[@]}"
    [[ "$mode" == "clean" ]] && echo "🧹 Cleaned: $label" || echo "✅ Finished: $label"
  else
    gum spin --spinner dot --title "Running $label..." -- bash -c "bash \"$script\" \"$mode\" ${FLAGS[*]}" >/dev/null
    [[ "$mode" == "clean" ]] && gum style --foreground 8 "✔️  $label cleaned" ||
      gum style --foreground 10 "✔️  $label finished"
  fi
}

main() {
  local all_names=()
  local preselect=()
  declare -A label_to_name=()
  local menu_labels=()

  # Build menu and preselect based on actual installed state
  for name in "${!MODULES[@]}"; do
    all_names+=("$name")
    local label="$name"
    [[ -n "${MODULE_DESCRIPTIONS[$name]}" ]] && label="$name – ${MODULE_DESCRIPTIONS[$name]}"
    menu_labels+=("$label")
    label_to_name["$label"]="$name"

    module_installed "$name" && preselect+=("$label")
  done

  local SELECTED_ARGS=()
  for item in "${preselect[@]}"; do SELECTED_ARGS+=(--selected "$item"); done

  local selected_labels=()
  IFS=$'\n' read -r -d '' -a selected_labels < <(
    printf "%s\n" "${menu_labels[@]}" | sort |
      gum choose --no-limit "${SELECTED_ARGS[@]}" \
        --header="Select optional apps to install (unchecked = uninstall)" --height=15 && printf '\0'
  )

  declare -A SELECTED_NEW=()
  for label in "${selected_labels[@]}"; do
    name="${label_to_name[$label]}"
    SELECTED_NEW["$name"]=1
  done

  # Load prior selections (still written for reference, but we base actions on installed state)
  declare -A SELECTED_OLD=()
  [[ -f "$STATE_FILE" ]] && while read -r name; do [[ -n "$name" ]] && SELECTED_OLD["$name"]=1; done <"$STATE_FILE"

  local requires_sudo=false
  local will_run_any=false

  # First pass: decide actions based on "installed now" vs "selected now"
  for name in "${all_names[@]}"; do
    local now="${SELECTED_NEW[$name]:-}"
    local script="$MODULE_DIR/install-$name.sh"
    local is_installed=false
    if module_installed "$name"; then is_installed=true; fi

    if [[ "$now" == "1" && "$is_installed" == "false" ]]; then
      # Need to install
      will_run_any=true
      needs_sudo "$script" "all" && requires_sudo=true
    elif [[ "$now" != "1" && "$is_installed" == "true" ]]; then
      # Need to clean/uninstall
      will_run_any=true
      needs_sudo "$script" "clean" && requires_sudo=true
    fi
  done

  # Prompt for sudo only if needed
  if $requires_sudo; then
    echo "🔐 Administrative privileges are required for selected changes..."
    if sudo -v; then
      gum style --foreground 10 "✅ Sudo access granted."
      while true; do
        sleep 60
        sudo -n true 2>/dev/null || true
      done &
      SUDO_KEEP_ALIVE_PID=$!
      trap 'kill "$SUDO_KEEP_ALIVE_PID" 2>/dev/null || true' EXIT
      export GLIMT_NO_SUDO_PROMPT=1
    else
      echo "❌ Sudo access is required for these extras."
      exit 1
    fi
  fi

  # Second pass: execute actions
  for name in "${all_names[@]}"; do
    local now="${SELECTED_NEW[$name]:-}"
    local is_installed=false
    if module_installed "$name"; then is_installed=true; fi

    if [[ "$now" == "1" && "$is_installed" == "false" ]]; then
      run_module_script "$name" "all"
    elif [[ "$now" != "1" && "$is_installed" == "true" ]]; then
      run_module_script "$name" "clean"
    fi
  done

  $will_run_any || echo "ℹ️  No changes selected."
  printf "%s\n" "${!SELECTED_NEW[@]}" >"$STATE_FILE"
}

# === Entry point ===
case "$ACTION" in
all | install) main ;;
*)
  echo "Usage: $0 [--verbose|--quiet] [all|install]"
  exit 1
  ;;
esac
