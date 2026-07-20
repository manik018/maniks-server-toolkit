# Changelog

## 1.0.5

- All monitoring module commands now persist MRRF1 aggregate reports to the state directory.
- The unified report engine discovers persisted reports for all six modules.

## 0.1.0 - 2026-07-17

- Architecture approved and frozen.
- Replaced the prototype monitoring code with foundation-only implementation aligned to the frozen architecture.
- Added the CLI framework, dispatcher, shared library loader, layered configuration, logging, errors, output, dependency detection, and flock-based locking foundation.
- Added secure foundation installer and uninstaller with dry-run support.
- Added foundation tests and developer utilities.
- Added Health Module v1 with isolated CPU, memory, disk, uptime, and system collectors plus terminal rendering and MRRF1 aggregate generation.
- Added Services Module v1 with isolated systemd-based service collectors, terminal rendering, and MRRF1 aggregate generation.
- Added Security Module v1 with isolated SSH, UFW, Fail2Ban, unattended-upgrades, and time-sync collectors plus terminal rendering and MRRF1 aggregate generation.
- Added Website Module v1 with isolated curl-based website checks, TLS inspection, terminal rendering, and MRRF1 aggregate generation.
- Added WordPress Module v1 with read-only WP-CLI, REST, and wp-config inspection plus terminal rendering and MRRF1 aggregate generation.
- Added Backup Module v1 with local filesystem and optional rclone metadata checks plus terminal rendering and MRRF1 aggregate generation.
- Added Report Engine v1 for unified terminal rendering from existing MRRF1 aggregate reports.
- Added Telegram Module v1 for sanitized, bounded delivery of pre-rendered text through the Telegram Bot API.
- Added Alert Engine v1 for policy-only alert decisions, cooldowns, repeats, recovery detection, and minimal state tracking.
