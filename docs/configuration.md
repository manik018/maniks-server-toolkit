# Configuration

Primary configuration file:

- `/etc/mst/config.conf`

Security notes:

- Foundation phase configuration is limited to runtime behavior only
- Runtime roots are determined internally; `MST_ROOT` from the environment is never trusted
- Runtime write destinations are accepted only under validated MST-owned paths
- Keep the file owned by root
- Use mode `600` where practical
- Invalid runtime values are rejected at startup
- Health thresholds are read-only observation thresholds only; they do not trigger remediation

Key settings:

- `MST_CONFIG_SCHEMA_VERSION`
- `MST_LOG_LEVEL`
- `MST_OUTPUT_MODE`
- `MST_COLOR_MODE`
- `MST_LOG_DIR`
- `MST_STATE_DIR`
- `MST_LOCK_DIR`
- `MST_TIMEOUT_SECONDS`
- `MST_ALLOW_ENV_OVERRIDES`
- `MST_HEALTH_CPU_WARN_PERCENT`
- `MST_HEALTH_CPU_ERROR_PERCENT`
- `MST_HEALTH_MEMORY_WARN_PERCENT`
- `MST_HEALTH_MEMORY_ERROR_PERCENT`
- `MST_HEALTH_DISK_WARN_PERCENT`
- `MST_HEALTH_DISK_ERROR_PERCENT`

Default health thresholds:

- CPU warning `80`
- CPU error `95`
- Memory warning `85`
- Memory error `95`
- Disk warning `85`
- Disk error `95`
