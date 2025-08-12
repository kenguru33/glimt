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

# === Define modules: [name]=binary
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
  [discord]="Voice, video, and text chat platform"
)

# --- Helper: check if module script likely needs sudo
needs_sudo() {
  local script="$1"
  local mode="${2:-all}"
  [[ -x "$script" ]] || return 1

  # Probe mode if script supports it
  if "$script" --requires-sudo "$mode" >/dev/null 2>&1; then
    return 0
  fi

  # Heuristic search for privileged commands
  grep -Eq \
    '(^|[^[:alnum:]_])(apt(-get)?[[:space:]]+(install|remove|purge)|dpkg[[:space:]]+-i|flatpak[[:space:]]+(install|uninstall)|snap[[:space:]]+(install|remove)|systemctl[[:space:]]+(enable|disable|start|stop)|update-alternatives|(^|[[:space:]])cp[[:space:]]+.*\s/(usr|etc)/|(^|[[:space:]])install[[:space:]]+.*\s/(usr|etc)/)' \
    "$script"
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

  for name in "${!MODULES[@]}"; do
    all_names+=("$name")
    local label="$name"
    [[ -n "${MODULE_DESCRIPTIONS[$name]}" ]] && label="$name – ${MODULE_DESCRIPTIONS[$name]}"
    menu_labels+=("$label")
    label_to_name["$label"]="$name"
    command -v "${MODULES[$name]}" &>/dev/null && preselect+=("$label")
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
  declare -A SELECTED_OLD=()

  for label in "${selected_labels[@]}"; do
    name="${label_to_name[$label]}"
    SELECTED_NEW["$name"]=1
  done

  [[ -f "$STATE_FILE" ]] && while read -r name; do [[ -n "$name" ]] && SELECTED_OLD["$name"]=1; done <"$STATE_FILE"

  local requires_sudo=false
  local will_run_any=false

  # First pass: check what will run and if sudo is needed
  for name in "${all_names[@]}"; do
    local was="${SELECTED_OLD[$name]:-}"
    local now="${SELECTED_NEW[$name]:-}"
    local script="$MODULE_DIR/install-$name.sh"

    if [[ "$now" == "1" && "$was" != "1" ]]; then
      will_run_any=true
      needs_sudo "$script" "all" && requires_sudo=true
    elif [[ "$now" != "1" && "$was" == "1" ]]; then
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

  # Second pass: run the changes
  for name in "${all_names[@]}"; do
    local was="${SELECTED_OLD[$name]:-}"
    local now="${SELECTED_NEW[$name]:-}"
    if [[ "$now" == "1" && "$was" != "1" ]]; then
      run_module_script "$name" "all"
    elif [[ "$now" != "1" && "$was" == "1" ]]; then
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
