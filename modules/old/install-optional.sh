#!/bin/bash
set -e

trap 'echo "❌ An error occurred in optional desktop setup." >&2' ERR

# === Parse flags and action ===
SHOW_OUTPUT="${SHOW_OUTPUT:-0}"
ACTION=""
FLAGS=()

for arg in "$@"; do
  case "$arg" in
    --verbose)
      SHOW_OUTPUT=1
      FLAGS+=("$arg")
      ;;
    --quiet)
      SHOW_OUTPUT=0
      FLAGS+=("$arg")
      ;;
    all|install)
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
MODULE_DIR="./modules"

# === Always-included terminal tools ===
declare -A MODULES_TERMINAL=(
  [1password-cli]="command -v op"
  [zellij]="command -v zellij"
  [k9s]="command -v k9s"
)

# === GNOME-specific desktop tools ===
declare -A MODULES_GNOME=(
  [1password]="command -v 1password"
  [chrome]="command -v google-chrome"
  [vscode]="command -v code"
  [kitty]="command -v kitty"
  [lens]="command -v lens"
  [jetbrains-toolbox]="command -v jetbrains-toolbox"
  [firefox-pwa]="command -v firefoxpwa"
  [blackbox-terminal]="command -v blackbox-terminal"
)

# === Merge into final MODULES ===
declare -A MODULES
for key in "${!MODULES_TERMINAL[@]}"; do
  MODULES["$key"]="${MODULES_TERMINAL[$key]}"
done

if command -v gnome-shell &>/dev/null; then
  for key in "${!MODULES_GNOME[@]}"; do
    MODULES["$key"]="${MODULES_GNOME[$key]}"
  done
fi

# === Run module script with spinner or full output ===
run_installer_for() {
  local name="$1"
  local script="$MODULE_DIR/install-$name.sh"

  if [[ ! -f "$script" ]]; then
    echo "⚠️ Missing script: $script"
    return
  fi

  local cmd=(bash "$script" all "${FLAGS[@]}")

  if [[ "$SHOW_OUTPUT" == "1" ]]; then
    echo "▶️ Installing $name..."
    "${cmd[@]}"
  else
    gum spin --title "Installing $name..." -- bash -c "${cmd[*]}"
  fi
}

main() {
  local list=()
  local preselect=()

  for name in "${!MODULES[@]}"; do
    list+=("$name")
    if eval "${MODULES[$name]}" &>/dev/null; then
      preselect+=("$name")
    fi
  done

  local SELECTED_ARGS=()
  for item in "${preselect[@]}"; do
    SELECTED_ARGS+=(--selected "$item")
  done

  local selected=()
  IFS=$'\n' read -r -d '' -a selected < <(
    printf "%s\n" "${list[@]}" | gum choose --no-limit "${SELECTED_ARGS[@]}" \
      --header="Select optional apps to install" --height=15 && printf '\0'
  )

  [[ ${#selected[@]} -eq 0 ]] && echo "❌ Nothing selected. Skipping." && exit 0

  for name in "${selected[@]}"; do
    run_installer_for "$name"
  done
}

# === Entry point ===
case "$ACTION" in
  all|install)
    main
    ;;
  *)
    echo "Usage: $0 [--verbose|--quiet] [all|install]"
    exit 1
    ;;
esac
