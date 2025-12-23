# Fedora 43 Setup Guide

## Overview

Glimt now supports **Fedora 43** (and other Fedora-based distributions) in addition to Debian. The setup automatically detects your OS and uses the appropriate package manager and modules.

## What's Included

### Core Modules (Fedora)
- **Zsh** - Modern shell with plugins
- **Starship** - Fast, customizable prompt
- **Git Config** - Git configuration with user prompts
- **FZF** - Fuzzy finder with fzf-tab plugin
- **Eza** - Modern `ls` replacement
- **Neovim** - Modern vim editor
- **Nerd Fonts** - Programming fonts (Hack, FiraCode, JetBrainsMono)
- **GNOME Config** - Desktop configuration and wallpaper
- **GNOME Terminal Theme** - Catppuccin theme
- **Blackbox Terminal** - Modern terminal (via Flatpak)

### Package Manager Differences

Fedora uses **DNF** instead of APT:
- `sudo dnf makecache -y` instead of `sudo apt update`
- `sudo dnf install -y <package>` instead of `sudo apt install -y <package>`
- `rpm -q <package>` instead of `dpkg -s <package>` for checking installed packages

## Installation

### From Bootstrap Script

```bash
bash <(wget -qO- https://raw.githubusercontent.com/kenguru33/glimt/main/bootstrap.sh)
```

The bootstrap script will:
1. Detect your OS (Fedora/Debian)
2. Clone/update the repository
3. Run the appropriate setup script

### Manual Installation

```bash
git clone https://github.com/kenguru33/glimt.git ~/.glimt
cd ~/.glimt
bash setup.sh
```

## Module Structure

Fedora modules are located in `modules/fedora/`:
- Core modules: `modules/fedora/install-*.sh`
- Optional extras: `modules/fedora/extras/install-*.sh`
- Config templates: `modules/fedora/config/*`

## Using Glimt CLI

The `glimt` command automatically detects your OS:

```bash
# Update all modules
glimt update

# Install a specific module
glimt install zsh

# Clean a module
glimt clean starship

# Interactive module selection (extras)
glimt module-selection
```

## Adding New Fedora Modules

To add a new module for Fedora:

1. Create `modules/fedora/install-<name>.sh`
2. Follow the standard module pattern:
   ```bash
   #!/bin/bash
   ACTION="${1:-all}"
   
   deps() {
     sudo dnf makecache -y
     sudo dnf install -y <packages>
   }
   
   install() {
     # Installation logic
   }
   
   config() {
     # Configuration logic
   }
   
   clean() {
     # Cleanup logic
   }
   
   case "$ACTION" in
     all)    deps; install; config ;;
     deps)   deps ;;
     install) install ;;
     config) config ;;
     clean)  clean ;;
   esac
   ```

3. Make it executable: `chmod +x install-<name>.sh`

## Differences from Debian Setup

1. **Package Manager**: DNF vs APT
2. **Package Names**: Some packages have different names
   - `fd-find` (Debian) vs `fd` (Fedora)
   - `batcat` (Debian) vs `bat` (Fedora)
3. **Repositories**: Fedora uses RPM Fusion, COPR, etc.
4. **Flatpak**: More commonly used on Fedora for desktop apps

## Troubleshooting

### Gum Not Available
If `gum` is not in Fedora repos, it will try to install via Go. Install Go first:
```bash
sudo dnf install -y golang
```

### Eza Not in Default Repos
Eza may require COPR repository:
```bash
sudo dnf copr enable -y eza-community/eza
sudo dnf install -y eza
```

### Flatpak Not Installed
Some modules require Flatpak:
```bash
sudo dnf install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
```

## Status

✅ Core modules implemented
✅ OS detection working
✅ Package manager abstraction
✅ Config directory structure
✅ Priority modules (GNOME, fonts, terminal)
⏳ Additional modules can be added as needed

## Contributing

When adding new modules, ensure:
- OS detection checks for Fedora
- Uses `dnf` instead of `apt`
- Uses `rpm -q` for package checking
- Handles Fedora-specific package names
- Tests on Fedora 43

