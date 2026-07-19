# Installation

## Foundation Phase

Foundation implementation installs only the secure runtime, not monitoring features.

Supported working commands after installation:

- `mst`
- `mst help`
- `mst version`
- `mst doctor`

All monitoring commands currently return `NOT IMPLEMENTED`.

## Ubuntu 24.04 LTS

```bash
sudo ./install.sh --dry-run --verbose
sudo ./install.sh --non-interactive
sudo mst doctor
```

## Installer Behavior

The installer:

- verifies Ubuntu 24.04
- verifies architecture
- verifies required binaries
- supports dry-run
- supports verbose mode
- supports non-interactive mode
- installs the foundation runtime only
- preserves existing configuration
- installs logrotate configuration
- can optionally install a commented cron template

## Fixed Installation Paths

This version of MST uses fixed installation paths only:

- `/usr/local/bin/mst`
- `/usr/local/lib/mst`
- `/etc/mst`
- `/var/log/mst`
- `/var/lib/mst`
- `/var/lib/mst/locks`

Custom installation prefixes are not supported. Environment overrides such as `PREFIX`, `BIN_DIR`, `LIB_DIR`, and `CONFIG_DIR` must be unset before running `install.sh`.
