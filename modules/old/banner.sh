#!/bin/bash
set -e

# Show a styled logo banner using figlet + gum
show_banner() {
  if ! command -v figlet &>/dev/null; then
    echo "❌ figlet is not installed. Skipping banner."
    return
  fi

  if ! command -v gum &>/dev/null; then
    echo "❌ gum is not installed. Skipping banner."
    return
  fi

  logo=$(figlet "After Install")

  echo "$logo" | gum style \
    --foreground 212 \
    --margin "1 2" \
    --padding "1 4"

  echo
  gum style \
    --foreground 244 \
    --align center \
    --width 60 \
    --padding "0 1" \
    "A post-install automation tool to customize your Linux desktop with themes, terminals, fonts, and extensions."
  echo
}

show_banner
