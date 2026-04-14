# ✨ G L I M T ✨

**Glimt** is an opinionated post-installation tool for **Fedora**. It takes a fresh install from zero to a fully configured development environment — shell, GNOME desktop, Kubernetes tooling, and selected apps — in a single command.

---

## Install

```bash
bash <(wget -qO- https://raw.githubusercontent.com/kenguru33/glimt/main/bootstrap.sh)
```

To run the development branch:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/kenguru33/glimt/main/bootstrap.sh) branch=dev
```

> Do **not** run as `root`. Your user must have **sudo** privileges.

---

## What gets installed

### Shell & terminal

| Module | What it does |
|---|---|
| `zsh-env` | ZSH with config scaffolding (`~/.zsh/config/*.zsh`) |
| `starship` | Starship prompt |
| `fzf` | Fuzzy finder |
| `bat` | `cat` with syntax highlighting |
| `eza` | Modern `ls` replacement |
| `btop` | Resource monitor |
| `wl-copy` | `pbcopy` / `pbpaste` Wayland clipboard helpers |
| `zellij` | Terminal multiplexer *(extras)* |
| `kitty` | Kitty terminal *(extras)* |
| `blackbox-terminal` | BlackBox terminal *(extras)* |

### Development tools

| Module | What it does |
|---|---|
| `git-config` | Git with GNOME Keyring credential store |
| `nvim` | Neovim |
| `lazyvim` | LazyVim config for Neovim |
| `volta` | Node.js version manager |
| `dotnet-userspace` | .NET SDK 8 and 10 (userspace install, no sudo) *(extras)* |
| `vscode` | Visual Studio Code *(extras)* |
| `jetbrains-toolbox` | JetBrains Toolbox *(extras)* |

### Kubernetes & cloud

| Module | What it does |
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

| Module | What it does |
|---|---|
| `gnome-config` | Wallpaper, UI preferences, keybindings |
| `gnome-extensions` | Tiling Shell, Blur My Shell, GSConnect, AppIndicator |
| `ptyxis-theme` | Catppuccin Mocha palette applied to all Ptyxis profiles |
| `nerdfonts` | Nerd Fonts |
| `papirus-icon-theme` | Papirus icon theme |
| `set-user-avatar` | Gravatar-based GNOME user avatar |

### System

| Module | What it does |
|---|---|
| `flatpak` | Flatpak + Flathub |
| `chrome` | Google Chrome |
| `norwegian-mac-keyboard` | Norwegian Mac keyboard layout |
| `snapper` | Snapper snapshots on Btrfs root (auto-detected), dnf pre/post hooks, COW disabled for VM images |

### Applications *(extras, opt-in)*

| Module | What it installs |
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
glimt update                # pull latest glimt and re-run
```

`glimt install <TAB>` and `glimt clean <TAB>` tab-complete all available module names.

---

## Git credentials

Git is configured to use `git-credential-libsecret` (GNOME Keyring). If the keyring socket is not running:

```bash
systemctl --user enable --now gnome-keyring-daemon.socket
```

---

<img src="./screenshot.png" alt="Glimt screenshot" width="400">
