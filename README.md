<div align="center">

# ✨ Glimt — Fedora Post-Install Automation

**One command. Fully configured Fedora developer workstation.**

Stop reinstalling the same tools after every fresh Fedora install. Glimt automates your entire setup — shell, GNOME, Kubernetes tooling, and developer apps — and keeps it reproducible.

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Platform: Fedora](https://img.shields.io/badge/platform-Fedora-294172)
![Shell: Bash](https://img.shields.io/badge/shell-bash-89e051)

<br>

```bash
bash <(wget -qO- https://raw.githubusercontent.com/kenguru33/glimt/main/bootstrap.sh)
```

<br>

<img src="./screenshot.png" alt="Glimt running on Fedora Workstation — post-install automation" width="720">

</div>

---

## What is Glimt?

Glimt is a post-install automation tool for Fedora Workstation. After a fresh install, a single command sets up your entire development environment — ZSH with Starship, a tuned GNOME desktop, Kubernetes CLI tools, Neovim, Node.js, Btrfs snapshots, and more.

No Ansible. No YAML. No dependencies. Just Bash.

---

## Why Glimt?

Reinstalling Fedora means hours of repetitive work — `dnf install`, GNOME tweaks, binary downloads, dotfiles. Glimt does all of it in one run, and a post-install CLI lets you manage modules individually afterwards.

- **Idempotent** — run it as many times as you like, it won't break anything
- **Modular** — every tool is its own script; install, clean, or reconfigure individually
- **Opt-in extras** — core modules run automatically, optional apps are picked interactively
- **No root required** — runs as your normal user, only calls `sudo` when necessary

---

## 📦 What you get

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

## 🎛️ Extras — pick what you need

Optional modules are presented in an interactive picker during setup. Add or remove them any time.

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

**Git credentials** — uses `git-credential-libsecret` backed by GNOME Keyring. Enable the socket if needed:

```bash
systemctl --user enable --now gnome-keyring-daemon.socket
```

---

## About

Glimt is a Fedora Workstation post-install automation tool written in Bash. Built for developers who reinstall Fedora regularly and want a reproducible environment without heavyweight orchestration tools.

**Keywords:** Fedora post-install script, Fedora workstation setup, automate Fedora, Fedora developer environment, Fedora dotfiles, Fedora fresh install, GNOME setup script, Fedora bash script, Fedora workstation automation
