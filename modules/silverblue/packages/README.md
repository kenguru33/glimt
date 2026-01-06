# rpm-ostree Packages

This folder contains the list of packages that are installed via `rpm-ostree` in the Silverblue module.

## Package List

See `rpm-ostree-packages.txt` for the complete list of packages.

## Installation

All packages can be installed using the `install-silverblue-prereq.sh` script (located in this `packages/` folder):

```bash
./modules/silverblue/packages/install-silverblue-prereq.sh all
```

Or from the silverblue module directory:

```bash
./packages/install-silverblue-prereq.sh all
```

## Individual Package Scripts

⚠️ **Note**: Individual install scripts for these packages have been moved to `not_used/` folder:
- `install-jq.sh` - JSON processor (moved to `not_used/`)
- `install-wl-clipboard.sh` - Wayland clipboard utilities (moved to `not_used/`)
- `install-1password.sh` - 1Password password manager (moved to `not_used/`)

These are no longer used. All packages should be installed via `install-silverblue-prereq.sh` instead.

Other packages still have their own install scripts:
- `install-zsh.sh` - Z shell (still in use)
- `install-curl.sh` - curl (if it exists, though curl is handled by prereq)

## Important Notes

⚠️ **Reboot Required**: After installing packages via `rpm-ostree`, a system reboot is required for the changes to take effect.

## Package Details

### curl
- **Purpose**: Command-line tool for transferring data
- **Used by**: volta module (prerequisite)
- **Install**: `sudo rpm-ostree install -y curl`

### jq
- **Purpose**: JSON processor for command-line
- **Install**: `sudo rpm-ostree install -y jq`

### zsh
- **Purpose**: Z shell with enhanced features
- **Install**: `sudo rpm-ostree install -y zsh`

### wl-clipboard
- **Purpose**: Wayland clipboard utilities (wl-copy, wl-paste)
- **Install**: `sudo rpm-ostree install -y wl-clipboard`

### 1password
- **Purpose**: Password manager
- **Repository**: Requires 1Password repository setup
- **Install**: `sudo rpm-ostree install -y 1password`
