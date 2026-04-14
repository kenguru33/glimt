# Glimt

> Opinionated post-installation automation for Fedora — from a fresh install to a fully configured development environment in a single command.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Platform: Fedora](https://img.shields.io/badge/platform-Fedora-294172)
![Shell: Bash](https://img.shields.io/badge/shell-bash-89e051)

<img src="./screenshot.png" alt="Glimt screenshot" width="720">

---

## Quick start

```bash
bash <(wget -qO- https://raw.githubusercontent.com/kenguru33/glimt/main/bootstrap.sh)
```

> **Requirements:** Do not run as `root`. Your user must have `sudo` privileges.

To run the development branch:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/kenguru33/glimt/main/bootstrap.sh) branch=dev
```

---

## What gets installed

### Shell & terminal

| Module | Description |
|---|---|
| `zsh-env` | ZSH with config scaffolding (`~/.zsh/config/*.zsh`) |
| `starship` | Starship prompt |
| `fzf` | Fuzzy finder |
| `bat` | `cat` with syntax highlighting |
| `eza` | Modern `ls` replacement |
| `btop` | Resource monitor |
| `wl-copy` | Wayland clipboard helpers (`pbcopy` / `pbpaste`) |
| `zellij` | Terminal multiplexer *(extras)* |
| `kitty` | Kitty terminal *(extras)* |
| `blackbox-terminal` | BlackBox terminal *(extras)* |

### Development tools

| Module | Description |
|---|---|
| `git-config` | Git with GNOME Keyring credential store |
| `nvim` | Neovim |
| `lazyvim` | LazyVim config for Neovim |
| `volta` | Node.js version manager |
| `dotnet-userspace` | .NET SDK 8 and 10 — userspace install, no sudo *(extras)* |
| `vscode` | Visual Studio Code *(extras)* |
| `jetbrains-toolbox` | JetBrains Toolbox *(extras)* |

### Kubernetes & cloud

| Module | Description |
|---|---|
| `kubectl` | kubectl |
| `kubectx` | `kubens` / `kubectx` |
| `k9s` | k9s TUI |
| `helm` | Helm |
| `azure-cli` | Azure CLI |
| `lens` | Lens Kubernetes desktop *(extras)* |
| `lazydocker` | LazyDocker TUI *(extras)* |
| `docker-rootless` | Docker rootless mode *(extras)* |

### GNOME desktop

| Module | Description |
|---|---|
| `gnome-config` | Wallpaper, UI preferences, keybindings |
| `gnome-extensions` | Tiling Shell, Blur My Shell, GSConnect, AppIndicator |
| `ptyxis-theme` | Catppuccin Mocha palette applied to all Ptyxis profiles |
| `nerdfonts` | Nerd Fonts |
| `papirus-icon-theme` | Papirus icon theme |
| `set-user-avatar` | Gravatar-based GNOME user avatar |

### System

| Module | Description |
|---|---|
| `flatpak` | Flatpak + Flathub |
| `chrome` | Google Chrome |
| `norwegian-mac-keyboard` | Norwegian Mac keyboard layout |
| `snapper` | Snapper snapshots on Btrfs root (auto-detected), dnf pre/post hooks, COW disabled for VM images |

### Applications *(extras, opt-in)*

| Module | Installs |
|---|---|
| `1password` | 1Password GUI |
| `1password-cli` | 1Password CLI (`op`) |
| `discord` | Discord (Flatpak) |
| `spotify` | Spotify (Flatpak) |
| `gitkraken` | GitKraken |
| `tableplus` | TablePlus database client |
| `pika-backup` | Pika Backup |
| `notion-chrome` | Notion (Chrome PWA) |
| `outlook-pwa` | Outlook (Chrome PWA) |
| `teams-pwa` | Microsoft Teams (Chrome PWA) |
| `chatgpt-pwa` | ChatGPT (Chrome PWA) |
| `ytmusic-pwa` | YouTube Music (Chrome PWA) |

---

## Glimt CLI

After setup, `glimt` is available at `~/.local/bin/glimt`.

```bash
glimt install <module>      # install a module
glimt clean <module>        # uninstall a module
glimt module-selection      # interactive extras picker
glimt update                # pull latest and re-run
```

`glimt install <TAB>` and `glimt clean <TAB>` tab-complete all available module names.

---

## Notes

**Git credentials** — Git is configured to use `git-credential-libsecret` (GNOME Keyring). If the keyring socket is not running:

```bash
systemctl --user enable --now gnome-keyring-daemon.socket
```

**Extras** — Optional modules are selected via an interactive `gum`-based picker during setup. Re-running `glimt module-selection` lets you add or remove extras at any time; deselected modules are automatically cleaned up.
