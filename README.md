# Manik's Server Toolkit

Manik's Server Toolkit (MST) is an approved, security-first Linux server toolkit for Ubuntu 24.04 LTS. The architecture is frozen, the foundation is complete, and Health, Services, Security, Website, WordPress, Backup Module v1, Report Engine v1, Telegram Module v1, and Alert Engine v1 are now implemented.

## Foundation Commands

```bash
mst
mst help
mst version
mst doctor
mst health
mst services
mst security
mst website
mst wordpress
mst backup
mst report
mst telegram
mst alert
```

All monitoring commands except `mst health`, `mst services`, `mst security`, `mst website`, `mst wordpress`, `mst backup`, `mst report`, `mst telegram`, and `mst alert` currently return `NOT IMPLEMENTED`.

## Foundation Scope

- CLI framework
- command dispatcher
- shared library loader
- layered configuration loader and validator
- structured logging framework
- error and exit-code framework
- ANSI output helpers
- module discovery framework
- flock-based locking framework
- dependency detection
- secure installer and uninstaller
- dry-run infrastructure
- automated test scaffold
- developer utilities
- Health Module v1 for local operating-system health observation
- Services Module v1 for local systemd service observation
- Security Module v1 for local security posture observation
- Website Module v1 for configured website availability and TLS observation
- WordPress Module v1 for configured WordPress-specific health observation
- Backup Module v1 for configured backup freshness and metadata observation
- Report Engine v1 for unified terminal rendering from existing MRRF1 aggregate reports
- Telegram Module v1 for delivering pre-rendered text through the Telegram Bot API
- Alert Engine v1 for policy-only alert decisions from existing MRRF1 aggregate reports

See [Telegram Setup](docs/telegram-setup.md) for step-by-step Telegram bot setup.

## Architecture

- [Architecture Design Document](docs/architecture-design-document.md)
- [Engineering Review Report](docs/engineering-review-report.md)
- [MRRF1 JSON Schema Appendix](docs/mrrf1-json-schema-appendix.md)
- [Lockfile Metadata Appendix](docs/lockfile-metadata-appendix.md)
- [Release Artifacts](docs/release.md)

## Security

- [Zero-Risk Security Policy](SECURITY.md)
- Runtime roots and runtime write paths are resolved internally or via validated configuration only; inherited environment values are not trusted for code loading or filesystem writes.
