# MST v1.1.0

MST v1.1.0 adds Security Events monitoring to the daily server toolkit, extending unified reports and alerting with focused security activity checks.

- New `security_events` module, available through `mst security_events`.
- Incremental SSH login activity counts failed, accepted, and root-login attempts, with inode/byte-offset cursor tracking and log-rotation handling.
- Fail2Ban statistics report currently and total banned counts plus newly blocked IPs per configured jail, establishing a baseline on first run.
- New sudo group membership, root crontab and `/etc/cron.d/` changes, and available APT package updates are detected independently.
- Each check produces an MRRF1 record with an appropriate `ok`, `warn`, or `unavailable` status and can be configured separately.
- Unified reports, Telegram `telegram`, `digest`, `critical`, and `auto` styles, and the alert engine include Security Events alongside the original six modules.
- The daily monitoring script runs Security Events before alert evaluation.

Before enabling the new checks, review the `MST_SECURITY_EVENTS_*` configuration keys in `config/config.conf.example`. Sensible defaults are provided, but jail names and thresholds may need adjustment for your environment.
