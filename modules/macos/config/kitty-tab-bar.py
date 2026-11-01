# Glimt kitty tab titles (deployed to ~/.config/kitty/tab_bar.py).
#
# Used by `tab_title_template "{custom}"` in kitty.conf. Each tab is named
#   [session] project · title
# where "project" is the git repo (else folder) the tab works in and "title" is the window
# title. If any window in the tab runs Claude Code, its title (spinner/✳ plus
# the conversation topic) is shown even when another split has focus, so a
# tab running Claude stays recognisable. Shell titles that are just the cwd
# path are dropped, since the project name already says that.
#
# A window running zellij reports "session | pane title" (zellij's own format).
# zellij.zsh names sessions after the project, so the session becomes the
# project and the focused zellij pane's title (e.g. Claude's) the title.
#
# Anything unexpected falls back to kitty's own title: an exception here would
# otherwise leave the tab blank.
import os

from kitty.fast_data_types import get_boss


def _foreground(window):
    # 'claude', 'zellij' or None for the program running in the window.
    try:
        procs = window.child.foreground_processes
    except Exception:
        return None
    for proc in procs:
        for arg in (proc.get('cmdline') or [])[:2]:
            # Native installs run `claude`; npm installs run `node .../claude-code/cli.js`.
            if os.path.basename(arg) == 'claude' or '/claude-code/' in arg:
                return 'claude'
            if os.path.basename(arg) == 'zellij':
                return 'zellij'
    return None


_repo_roots = {}


def _repo_root(path):
    # Nearest parent holding .git (a dir, or a file in worktrees). Cached:
    # draw_title runs on every title change, i.e. every frame of Claude's spinner.
    if path not in _repo_roots:
        root, cur = None, path
        while cur and cur != '/':
            if os.path.exists(os.path.join(cur, '.git')):
                root = cur
                break
            cur = os.path.dirname(cur)
        _repo_roots[path] = root
    return _repo_roots[path]


def _project(path):
    # Name of the git repo the window works in, so a Claude session in a
    # subfolder (e.g. modules/macos) still shows the project; else the folder.
    if not path:
        return ''
    path = path.rstrip('/')
    home = os.path.expanduser('~')
    if not path or path == home:
        return '~'
    root = _repo_root(path)
    if root and root != home:
        path = root
    return os.path.basename(path)


def _draw(data):
    accessor = data['tab']
    tab = get_boss().tab_for_id(accessor.tab_id)
    title = data['title']
    cwd = accessor.active_oldest_wd
    project = None
    zellij = None
    if tab is not None:
        for window in tab:
            kind = _foreground(window)
            if kind == 'claude':
                title = window.title
                cwd = window.cwd_of_child or cwd
                zellij = None
                break
            if kind == 'zellij' and zellij is None:
                zellij = window
    if zellij is not None:
        project, _, title = zellij.title.partition(' | ')
    if not project:
        project = _project(cwd)
    if title.startswith(('~', '/')):
        title = ''
    session = data.get('session_name') or ''
    parts = '%s · %s' % (project, title) if project and title else (project or title)
    return ('[%s] ' % session if session else '') + parts


def draw_title(data):
    try:
        return _draw(data)
    except Exception:
        return data.get('title', '')
