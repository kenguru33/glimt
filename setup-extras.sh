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
  all | install)
    ACTION="$arg"
    ;;
  *)
    echo "❌ Unknown argument: $arg"
    echo "Usage: $0 [--verbose|--quiet] [all|install]"
    exit 1
    ;;
  esac
done

ACTION="${ACTION:-all}"
MODULE_DIR="./modules/debian/extras"
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
  [discord]="discord"
  #[gnome-boxes-tune]="$MODULE_DIR/install-gnome-boxes.tune.sh"
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
  #[gnome-boxes-tune]="Gnome Boxes (performance tuned)"
)

run_module_script() {
  local name="$1"
  local mode="$2"
  local script="$MODULE_DIR/install-$name.sh"
  local module_label="install-$name.sh"
  local label="$module_label"
  [[ "$mode" == "clean" ]] && label="$module_label ($mode)"

  if [[ ! -x "$script" ]]; then
    echo "⚠️  Missing or non-executable: $script"
    return
  fi

  if $VERBOSE; then
    echo "▶️  Running: $label"
    echo "ℹ️  ${MODULE_DESCRIPTIONS[$name]}"
    bash "$script" "$mode" "${FLAGS[@]}"
    if [[ "$mode" == "clean" ]]; then
      echo "🧹 Cleaned: $module_label"
    else
      echo "✅ Finished: $module_label"
    fi
  else
    gum spin --spinner dot --title "Running $label..." -- bash -c "bash \"$script\" \"$mode\" ${FLAGS[*]}" >/dev/null
    if [[ "$mode" == "clean" ]]; then
      gum style --foreground 8 "✔️  $module_label cleaned"
    else
      gum style --foreground 10 "✔️  $module_label finished"
    fi
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
    if [[ -n "${MODULE_DESCRIPTIONS[$name]}" ]]; then
      label="$name – ${MODULE_DESCRIPTIONS[$name]}"
    fi
    menu_labels+=("$label")
    label_to_name["$label"]="$name"

    if command -v "${MODULES[$name]}" &>/dev/null; then
      preselect+=("$label")
    fi
  done

  local SELECTED_ARGS=()
  for item in "${preselect[@]}"; do
    SELECTED_ARGS+=(--selected "$item")
  done

  local selected_labels=()
  IFS=$'\n' read -r -d '' -a selected_labels < <(
    printf "%s\n" "${menu_labels[@]}" | sort | gum choose --no-limit "${SELECTED_ARGS[@]}" \
      --header="Select optional apps to install (unchecked = uninstall)" --height=15 && printf '\0'
  )

  # Build selection maps
  declare -A SELECTED_NEW=()
  declare -A SELECTED_OLD=()

  for label in "${selected_labels[@]}"; do
    name="${label_to_name[$label]}"
    SELECTED_NEW["$name"]=1
  done

  if [[ -f "$STATE_FILE" ]]; then
    while read -r name; do
      [[ -n "$name" ]] && SELECTED_OLD["$name"]=1
    done <"$STATE_FILE"
  fi

  # Compare and run changed scripts only
  for name in "${all_names[@]}"; do
    local was="${SELECTED_OLD[$name]:-}"
    local now="${SELECTED_NEW[$name]:-}"

    if [[ "$now" == "1" && "$was" != "1" ]]; then
      run_module_script "$name" "all"
    elif [[ "$now" != "1" && "$was" == "1" ]]; then
      run_module_script "$name" "clean"
    fi
  done

  # Save updated state
  printf "%s\n" "${!SELECTED_NEW[@]}" >"$STATE_FILE"
}

# === Entry point ===
case "$ACTION" in
all | install)
  main
  ;;
*)
  echo "Usage: $0 [--verbose|--quiet] [all|install]"
  exit 1
  ;;
esac
