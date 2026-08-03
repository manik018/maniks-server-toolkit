# Changelog

## 1.1.1

- Hardened MRRF1 text handling by stripping ASCII control characters (`0x00`-`0x1F`) and DEL during sanitization and escaping. This ensures RFC 8259-compliant JSON output and prevents terminal escape sequences originating from attacker-influenced data, including HTTP response headers, redirect URLs, and WP-CLI output from compromised sites, from reaching administrator terminals or report consumers.

## 1.1.0

- Added the `security_events` module (`mst security_events`) with five independent checks: incremental SSH login activity, Fail2Ban jail statistics, new sudo group membership, cron configuration changes, and available APT package updates. Each check supports independent configuration and emits its own MRRF1 record with appropriate status.
- Unified reports, Telegram styles (`telegram`, `digest`, `critical`, and `auto`), and the alert engine now include `security_events` alongside the original six modules.
- `scripts/mst-daily-report.sh` now runs `security_events` in the daily monitoring pipeline.

## 1.0.6

### Telegram reporting and daily delivery

- Added Telegram-friendly report styles: `mst report --style telegram`, `digest`, `critical`, and `auto`, alongside the existing default text renderer.
- Added `scripts/mst-daily-report.sh` as a cron-oriented daily reporting entrypoint.
- Updated `templates/mst.cron.example` to document daily report delivery.
- Updated digest and full Telegram renderers to show human-readable disk usage with used/total GB and percentage instead of a bare status word.

### Website and WordPress target discovery

- Added optional, off-by-default website target discovery from local nginx/apache virtual host configuration with `MST_WEBSITE_AUTO_DISCOVER`.
- Added optional, off-by-default WordPress target discovery from local nginx/apache virtual host configuration with `MST_WORDPRESS_AUTO_DISCOVER`.
- Auto-discovered website and WordPress targets are merged with configured targets, while explicitly configured targets keep priority.

### WordPress false-positive fixes

- Fixed a false-positive WordPress critical status caused by WP-CLI refusing to run as root; WP-CLI invocations now add `--allow-root` only when MST is running as root.
- Fixed WordPress maintenance-mode parsing so WP-CLI output such as `Maintenance mode is not active.` is not misread as active.
- Fixed WordPress overdue cron-event counting. The inspector no longer relies on `wp cron event list --due-now --format=count`, which can return the full schedule size in some environments; it now compares each event's `next_run_gmt` timestamp to the current UTC time.

### Backup false-positive fixes

- Fixed rclone remote backup freshness checks for nested date-folder layouts such as `remote:backups/YYYY-MM-DD/HH.MM/home/site/backup.tar`.
- rclone metadata listing is now recursive, and directory entries are excluded so a dated folder is not selected as the latest backup object.

### Alert delivery confirmation

- Added `MST_ALERT_MIN_OCCURRENCES_BEFORE_DELIVERY`, defaulting to `2`, so a newly active warning or critical issue must be observed on consecutive alert evaluations before an out-of-band critical Telegram alert is sent.
- Routine daily digests continue to reflect the current run's status and are not gated by the alert confirmation threshold.
- Recovery notifications remain immediate and are not delayed by the confirmation threshold.
- Added a confirmed-active alert check used by the daily report entrypoint before sending the separate critical Telegram template.

### Alert report discovery

- Fixed `mst alert` with no module arguments so it auto-loads persisted reports for health, services, security, website, WordPress, and backup.
- Explicit `module=FILE` arguments continue to take precedence over persisted report discovery.

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
