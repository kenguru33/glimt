# ⌨️ Keyboard shortcuts

The shortcuts Glimt sets up on top of each application's defaults. Anything not listed here works as the application ships it.

---

## 🐱 kitty (macOS)

Configured in `~/.config/kitty/kitty.conf` (from `modules/macos/config/kitty.conf`).

### Splits

| Shortcut | Action |
|---|---|
| `⌘ D` | Vertical split — new window **to the right** (side by side) |
| `⌘ ⇧ D` | Horizontal split — new window **below** (stacked) |
| `⌘ ⌥ ←` `→` `↑` `↓` | Move focus to the split in that direction |

New splits open in the same folder as the window you split from.

### Sessions

A session is a saved set of tabs, splits, folders and running programs (for example Claude Code, btop and a shell side by side).

| Shortcut | Action |
|---|---|
| `⌃ ⇧ S` | **Save** the current session. Prompts for a name, pre-filled with the folder name |
| `⌃ ⇧ O` | **Open** a saved session (fzf picker; `Enter` opens, `Esc` cancels) |
| `⌃ ⇧ X` | **Close** the current session |
| `⌃ ⇧ ⌫` | **Delete** a saved session (fzf picker) |

Saved sessions live in `~/.local/share/kitty/sessions/`.

**Starting kitty with a session:** running `kitty` with no arguments from the shell opens

1. `.kitty.session` in the current folder, if there is one (a per-project layout), else
2. the default session `~/.config/kitty/default.session`.

Launching kitty from the Dock or Spotlight always opens the default session.

### Tab names

Tabs are named automatically as `[session] project · title`:

- **project** is the git repository the tab works in (or the folder name outside a repo).
- If a split in the tab runs **Claude Code**, the tab shows Claude's status and topic — `✳` when it is idle, a spinner while it works — even when another split has focus.
- 🔔 marks a tab in the background that rang the bell, e.g. Claude finishing or waiting for you.

---

## 🪟 zellij (optional extra, macOS and Fedora)

Configured in `~/.config/zellij/config.kdl` (from `modules/<os>/config/zellij.kdl`). The keys are zellij's **Unlock-First** preset.

### Locked and unlocked

zellij starts **locked**: every key goes to the program in the pane, so Claude Code's own shortcuts (`Ctrl+T`, `Ctrl+O`, `Ctrl+B`, …) work. To give zellij a command, unlock it first, then press a mode letter:

| Shortcut | Action |
|---|---|
| `⌃ G` | **Unlock** zellij. The status bar shows the mode letters |
| `⌃ G` / `Esc` / `Enter` | Lock again (from any mode) |
| `⌃ G` `p` | Pane mode |
| `⌃ G` `t` | Tab mode |
| `⌃ G` `r` | Resize mode |
| `⌃ G` `m` | Move mode |
| `⌃ G` `s` | Scroll mode |
| `⌃ G` `o` | Session mode |
| `⌃ G` `⌃ Q` | Quit zellij (the session ends; it can be resurrected later) |

Most actions lock zellij again by themselves, so `⌃ G` `p` `n` opens a pane and you are straight back in the program.

`⌃ G` is also Claude Code's "open in editor" key, so inside zellij that key unlocks zellij instead. To get the editor back, give it another key with `/keybindings` in Claude Code.

### Pane mode — `⌃ G` `p`

| Key | Action |
|---|---|
| `n` | New pane (zellij picks the direction) |
| `r` | New pane to the **right** |
| `d` | New pane **below** |
| `s` | New pane stacked on top of this one |
| `x` | Close the pane |
| `f` | Fullscreen on/off (`⇧ F`: also hide the bars) |
| `w` | Show/hide floating panes |
| `e` | Float the pane, or put a floating pane back in the layout |
| `i` | Pin a floating pane so it stays on top |
| `c` | Rename the pane (`Enter` saves, `Esc` undoes) |
| `z` | Pane frames on/off |
| `←` `↓` `↑` `→` or `h` `j` `k` `l` | Move focus |
| `Tab` / `;` | Next pane / last used pane |

### Tab mode — `⌃ G` `t`

| Key | Action |
|---|---|
| `n` | New tab |
| `x` | Close the tab |
| `r` | Rename the tab (`Enter` saves, `Esc` undoes) |
| `1`–`9` | Go to tab 1–9 |
| `←` `→` (or `h` `l`) | Previous / next tab |
| `Tab` | Last used tab |
| `b` | Break the pane out into a new tab |
| `[` / `]` | Move the pane to the tab on the left / right |
| `s` | Sync: type into every pane in the tab at once (on/off) |

Tabs are also renamed after the project automatically when you `cd` into another repo or open a new pane, which overwrites a name you set yourself.

### Resize mode — `⌃ G` `r`

| Key | Action |
|---|---|
| `←` `↓` `↑` `→` or `h` `j` `k` `l` | Grow the pane in that direction |
| `H` `J` `K` `L` | Shrink the pane from that side |
| `+` / `-` | Grow / shrink |

### Move mode — `⌃ G` `m`

| Key | Action |
|---|---|
| `←` `↓` `↑` `→` or `h` `j` `k` `l` | Swap the pane with its neighbour in that direction |
| `n` / `p` | Move the pane forward / backward in the layout |

### Scroll and search — `⌃ G` `s`

| Key | Action |
|---|---|
| `↑` `↓` or `j` `k` | Scroll a line |
| `d` / `u` | Half a page down / up |
| `PgDn` `PgUp` (or `⌃ F` `⌃ B`) | A page down / up |
| `[` / `]` | Jump to the previous / next shell prompt |
| `c` | Copy the last command's output |
| `e` | Open the scrollback in your editor |
| `f` | **Search**: type, `Enter`, then `n` / `p` next / previous match; `c` case, `w` wrap, `o` whole word |
| `⌃ C` | Back to the bottom and lock |

Selecting text with the mouse copies it to the clipboard.

### Session mode — `⌃ G` `o`

| Key | Action |
|---|---|
| `w` | Session manager: switch to, create or resurrect sessions |
| `d` | Detach (the session keeps running; reattach from the session manager or `zellij attach <name>`) |
| `c` | Settings |
| `l` | Layout manager |
| `p` | Plugin manager |
| `s` | Share the session in a browser |
| `a` | About zellij |

### Alt shortcuts (work while locked)

| Shortcut | Action |
|---|---|
| `Alt N` | New pane |
| `Alt ←` `→` `↑` `↓` (or `Alt H` `J` `K` `L`) | Move focus; left/right at the edge goes to the next tab |
| `Alt F` | Show/hide floating panes |
| `Alt =` / `Alt -` | Grow / shrink the pane |
| `Alt I` / `Alt O` | Move the tab left / right |
| `Alt [` / `Alt ]` | Previous / next layout for the panes in the tab |

`Alt P` is left out on purpose: it is Claude Code's model picker.

On **macOS**, kitty sends `⌥` as a character (`⌥ 7` → `|` on the Norwegian keyboard), not as Alt, so these shortcuts don't reach zellij there. Use the `⌃ G` modes instead. On **Fedora** they work as listed.

### Sessions

**Sessions are named after the project.** A new terminal opens a session named after the git repository you are in (`.glimt` → `glimt`), or the folder name outside a repo. If that session is already open in another terminal, you get `glimt-2`, `glimt-3`, …; an exited session is brought back instead, with its tabs and panes. Every pane shows its title in a title row, so a pane running Claude Code shows `✳` (idle) or a spinner (working) and the topic.

| Command | Action |
|---|---|
| `zellij list-sessions` | List sessions, live and exited |
| `zellij attach <name>` | Attach to a session |
| `zellij delete-session <name>` | Forget an exited session, so the next terminal starts blank |

To stop zellij from starting automatically, add `export GLIMT_ZELLIJ_AUTOSTART=0` to `~/.zshenv`.

---

## 🐚 Shell (zsh, macOS and Fedora)

| Shortcut | Action |
|---|---|
| `Tab` | Completion in an fzf picker with a preview of files and folders (fzf-tab). Type to filter, `Enter` to pick |
| `→` | Accept the grey suggestion from your history (zsh-autosuggestions) |

---

## 🇳🇴 Norwegian Mac keyboard (Fedora)

Applies when the **Norwegian (Macintosh)** layout is selected in GNOME. The left Option key works like on macOS:

| Shortcut | Character |
|---|---|
| `⌥ 7` | `\|` |
| `⌥ ⇧ 7` | `\` |

Log out and back in after installing for this to take effect.
