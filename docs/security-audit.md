# Security Audit - 2026-07-17

This audit was performed on Friday, July 17, 2026 before continuing development.

## Current Violations Found

1. `mst update` executed the installer directly, which violated the safe update policy.
2. Website checks used `curl -k`, which disabled TLS verification.
3. Website SSL inspection used `bash -c`, which is prohibited.
4. The installer did not support `--dry-run` and did not print a clear change plan before modifying the system.
5. The uninstaller used recursive deletion without validating ownership, symlinks, or MST-owned target paths.
6. Telegram delivery placed the bot token directly in the curl command line.
7. Config values and service names were not validated strongly enough before use.
8. Several checks returned guessed fallback values instead of explicit `UNKNOWN` semantics.
9. WordPress database verification used `wp db check`; this was removed in favor of safer read-only inspection.
10. Runtime file creation did not enforce a secure umask.

## Risky Design Choices Found

- Install target used `/opt/mst`; policy now standardizes on `/usr/local/lib/mst`.
- Cron file name was generic; policy now uses a dedicated MST-owned drop-in file.
- Some commands assumed elevated access instead of reporting reduced visibility safely.
- Backup path handling trusted configured paths too broadly.

## Remediation Plan

1. Replace the self-update path with a manual instruction command.
2. Add secure config, path, URL, hostname, and service-name validation helpers.
3. Enforce `umask 027` and secure file permissions.
4. Rework installer and uninstaller around explicit MST-owned paths, dry-run support, and symlink protection.
5. Rework Telegram delivery to avoid exposing the token in process arguments where practical.
6. Remove insecure TLS options and prohibited shell execution patterns.
7. Make failure behavior explicit with `UNKNOWN` and sanitized logs.
8. Document the security policy and per-module review expectations in the repo.

## Files Requiring Changes

- `install.sh`
- `uninstall.sh`
- `mst`
- `README.md`
- `config/config.conf.example`
- `lib/common.sh`
- `lib/config.sh`
- `lib/logging.sh`
- `lib/system.sh`
- `lib/telegram.sh`
- `modules/health.sh`
- `modules/security.sh`
- `modules/services.sh`
- `modules/website.sh`
- `modules/wordpress.sh`
- `modules/backup.sh`
- `modules/doctor.sh`
- `modules/report.sh`
- `modules/utilities.sh`
- `tests/test_runner.sh`
- `templates/logrotate.conf`

