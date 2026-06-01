<div align="center">

# ✨ Glimt — Fedora & macOS Post-Install Automation

**One command. A fully configured developer workstation — on Fedora or macOS.**

Stop reinstalling the same tools after every fresh install. Glimt automates your entire setup — shell, desktop tweaks, Kubernetes tooling, and developer apps — and keeps it reproducible.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Platform: Fedora](https://img.shields.io/badge/platform-Fedora-294172)
![Platform: macOS](https://img.shields.io/badge/platform-macOS-000000)
![Shell: Bash](https://img.shields.io/badge/shell-bash-89e051)

<br>

**Fedora**

```bash
bash <(wget -qO- https://raw.githubusercontent.com/kenguru33/glimt/main/bootstrap.sh)
```

**macOS** — a clean Mac ships with `curl` but not `wget`:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kenguru33/glimt/main/bootstrap.sh)
```

The bootstrap detects your OS, installs Git (via `xcode-select` on macOS), clones the repo to `~/.glimt`, and runs the right setup. On macOS it also installs Homebrew if missing.

<br>

<img src="./screenshot.png" alt="Glimt running on Fedora Workstation — post-install automation" width="720">

</div>

---

## What is Glimt?

Glimt is a post-install automation tool for **Fedora Workstation** and **macOS**. After a fresh install, a single command sets up your development environment.

- **On Fedora** — the full experience: ZSH with Starship, a tuned GNOME desktop, Kubernetes CLI tools, Neovim, Node.js, Btrfs snapshots, and more.
- **On macOS** — terminal tooling only (no desktop tweaks): the same ZSH/Starship/Neovim/Kubernetes stack, installed via Homebrew, plus optional GUI apps from Homebrew Casks and the Mac App Store.

No Ansible. No YAML. No dependencies. Just Bash.

---

## Why Glimt?

Reinstalling Fedora means hours of repetitive work — `dnf install`, GNOME tweaks, binary downloads, dotfiles. Glimt does all of it in one run, and a post-install CLI lets you manage modules individually afterwards.

- **Idempotent** — run it as many times as you like, it won't break anything
- **Modular** — every tool is its own script; install, clean, or reconfigure individually
- **Opt-in extras** — core modules run automatically, optional apps are picked interactively
- **No root required** — runs as your normal user, only calls `sudo` when necessary

---

## 📦 What you get on Fedora

### 💻 Shell & terminal

A modern ZSH environment configured and ready to go.

- **zsh** — ZSH with a clean config scaffold in `~/.zsh/config/`
- **starship** — Starship prompt with Catppuccin Mocha colors
- **nerdfonts** — Nerd Fonts patched for icons and glyphs
- **fzf** — fuzzy finder wired into shell history and file search
- **bat** — `cat` with syntax highlighting
- **eza** — modern `ls` replacement with icons and git status
- **btop** — resource monitor
- **pbcopy** — `pbcopy`/`pbpaste` for Wayland clipboard

### 🛠️ Development tools

- **git-config** — Git configured with GNOME Keyring credential storage
- **gh** — GitHub CLI with ZSH tab completion
- **nvim** — Neovim with LazyVim preconfigured
- **volta** — Node.js version manager, no sudo required

### ☸️ Kubernetes & cloud

- **kubectl** — Kubernetes CLI
- **helm** — Helm package manager
- **kubectx** — fast cluster and namespace switching (`kubectx`/`kubens`)
- **k9s** — terminal UI for Kubernetes clusters
- **azure-cli** — Azure CLI

### 🎨 GNOME desktop

A polished desktop with tiling, blur, Catppuccin terminal, and Papirus icons.

- **gnome-config** — wallpaper, UI tweaks, and keybindings
- **gnome-extensions** — Tiling Shell, Blur My Shell, GSConnect, AppIndicator
- **gnome-terminal-theme** — Catppuccin Mocha terminal color scheme
- **just-perfection** — fine-tune GNOME Shell UI elements
- **papirus-icon-theme** — Papirus icon theme
- **gnome-caffeine** — prevent screen lock on demand
- **gravatar** — sets your Gravatar as the user avatar

### ⚙️ System

- **flatpak** — Flatpak with Flathub configured
- **btrfs-config** — automatic Btrfs snapshots with snapper and dnf hooks
- **chrome** — Google Chrome
- **norwegian-mac-keyboard** — Norwegian Mac keyboard layout

---

## 🎛️ Fedora extras — pick what you need

Optional modules are presented in an interactive picker during setup. Add or remove them any time. (For the macOS extras list, see the [macOS](#-macos) section below.)

```bash
glimt module-selection
```

**🚀 Applications**
- `1password` — 1Password desktop + browser extension
- `1password-cli` — 1Password CLI (`op`)
- `discord` — Discord (Flatpak)
- `spotify` — Spotify (Flatpak)
- `gitkraken` — GitKraken Git client
- `tableplus` — TablePlus database GUI
- `pika` — Pika Backup

**🌐 Web apps**
- `notion` — Notion
- `outlook` — Outlook
- `teams` — Microsoft Teams
- `chatgpt` — ChatGPT
- `ytmusic` — YouTube Music

**🧰 Dev & infra**
- `vscode` — Visual Studio Code
- `jetbrains-toolbox` — JetBrains Toolbox
- `dotnet` — .NET SDK 8 + 10 (userspace install, no sudo)
- `docker-rootless` — Docker in rootless mode
- `lazydocker` — LazyDocker terminal UI
- `lens` — Lens Kubernetes desktop
- `zellij` — Zellij terminal multiplexer
- `claude-code` — Claude Code CLI

---

## 🍎 macOS

On macOS, Glimt installs **terminal tooling only** — no desktop or GNOME modules. Everything is installed through **Homebrew** (no `sudo` required for packages), and App Store apps are installed via [`mas`](https://github.com/mas-cli/mas).

**Core (installed automatically)**

- **zsh** + **starship** — ZSH with a Catppuccin Mocha Starship prompt
- **nerdfonts** — Nerd Fonts via Homebrew Casks
- **kitty** — GPU-accelerated terminal with a Catppuccin theme
- **fzf**, **bat**, **eza**, **btop**, **fastfetch**, **pbcopy** — modern shell utilities
- **git-config**, **gh** — Git + GitHub CLI
- **nvim** — Neovim with LazyVim
- **volta** — Node.js version manager
- **kubectl**, **k9s**, **kubectx**, **zellij** — Kubernetes & terminal tooling

**Extras — pick what you need** (`glimt module-selection`)

- **Apps** — `1password`, `1password-cli`, `tableplus`, `spotify`, `discord`
- **App Store** (via `mas`) — `amphetamine`, `magnet`, `things` (Things 3)
- **Web & desktop apps** — `notion`, `teams`, `chatgpt`, `ytmusic`, `claude-desktop`
- **Dev & infra** — `vscode`, `jetbrains-toolbox`, `dotnet`, `docker`, `lens`, `claude-code`

> macOS support is terminal-focused by design. The desktop, GNOME, and system modules listed above are Fedora-only.

**🔐 One optional permission**

To apply kitty's custom icon, Glimt edits `/Applications/kitty.app`, which macOS protects behind **App Management**. If you want the icon, grant your terminal app the permission *before* running setup:

1. **System Settings → Privacy & Security → App Management**
2. Enable your terminal app (Terminal, iTerm2, kitty, …)
3. **Quit and reopen** that terminal so the permission takes effect

This is entirely optional — without it, the icon step is skipped and setup continues normally. Nothing else in the macOS setup modifies protected system locations.

---

## 🖥️ Glimt CLI

After setup, `glimt` is installed to `~/.local/bin/glimt` with tab completion.

```bash
glimt install <module>      # install or reinstall a module
glimt clean <module>        # remove a module cleanly
glimt module-selection      # interactive extras picker
glimt update                # pull latest and re-run
```

---

## 📝 Notes

**Git credentials (Fedora)** — uses `git-credential-libsecret` backed by GNOME Keyring. Enable the socket if needed:

```bash
systemctl --user enable --now gnome-keyring-daemon.socket
```

---

## About

Glimt is a Fedora Workstation and macOS post-install automation tool written in Bash. Built for developers who reinstall regularly and want a reproducible environment without heavyweight orchestration tools.

**Keywords:** Fedora post-install script, Fedora workstation setup, automate Fedora, Fedora developer environment, Fedora dotfiles, Fedora fresh install, GNOME setup script, Fedora bash script, macOS setup script, macOS developer environment, Homebrew bootstrap, mac post-install automation, macOS dotfiles
