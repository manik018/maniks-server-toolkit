# MST v1.0.6 Release Notes

MST v1.0.6 updates the Telegram reporting pipeline and fixes several false-positive monitoring conditions in WordPress, backup, and alert evaluation workflows.

## Telegram reporting and daily delivery

- Added Telegram-friendly report styles: `mst report --style telegram`, `digest`, `critical`, and `auto`, alongside the existing default text renderer.
- Added `scripts/mst-daily-report.sh` as a cron-oriented daily reporting entrypoint.
- Updated `templates/mst.cron.example` to document daily report delivery.
- Updated digest and full Telegram renderers to show human-readable disk usage with used/total GB and percentage instead of a bare status word.

## Website and WordPress target discovery

- Added optional, off-by-default website target discovery from local nginx/apache virtual host configuration with `MST_WEBSITE_AUTO_DISCOVER`.
- Added optional, off-by-default WordPress target discovery from local nginx/apache virtual host configuration with `MST_WORDPRESS_AUTO_DISCOVER`.
- Auto-discovered website and WordPress targets are merged with configured targets, while explicitly configured targets keep priority.

## WordPress false-positive fixes

- Fixed a false-positive WordPress critical status caused by WP-CLI refusing to run as root; WP-CLI invocations now add `--allow-root` only when MST is running as root.
- Fixed WordPress maintenance-mode parsing so WP-CLI output such as `Maintenance mode is not active.` is not misread as active.
- Fixed WordPress overdue cron-event counting. The inspector no longer relies on `wp cron event list --due-now --format=count`, which can return the full schedule size in some environments; it now compares each event's `next_run_gmt` timestamp to the current UTC time.

## Backup false-positive fixes

- Fixed rclone remote backup freshness checks for nested date-folder layouts such as `remote:backups/YYYY-MM-DD/HH.MM/home/site/backup.tar`.
- rclone metadata listing is now recursive, and directory entries are excluded so a dated folder is not selected as the latest backup object.

## Alert delivery confirmation

- Added `MST_ALERT_MIN_OCCURRENCES_BEFORE_DELIVERY`, defaulting to `2`, so a newly active warning or critical issue must be observed on consecutive alert evaluations before an out-of-band critical Telegram alert is sent.
- Routine daily digests continue to reflect the current run's status and are not gated by the alert confirmation threshold.
- Recovery notifications remain immediate and are not delayed by the confirmation threshold.
- Added a confirmed-active alert check used by the daily report entrypoint before sending the separate critical Telegram template.

## Alert report discovery

- Fixed `mst alert` with no module arguments so it auto-loads persisted reports for health, services, security, website, WordPress, and backup.
- Explicit `module=FILE` arguments continue to take precedence over persisted report discovery.

This release supersedes v1.0.5. Upgrading is recommended for anyone running the Telegram alerting pipeline.
