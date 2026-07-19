# Architecture Change Log

## AR2 - Friday, July 17, 2026

- Replaced architecture draft with a simplified four-layer model.
- Removed speculative `telemetry-none` concept.
- Removed `assets/` from required architecture.
- Removed separate alert, report, score, and recommendation engine modules in favor of `lib/policy` plus renderers.
- Added formal normalized result schema `MRRF1`.
- Added explicit runtime loading model.
- Removed `--as-root-if-needed`.
- Added explicit privilege model based on operator-invoked elevation only.
- Added mandatory dependency policy and optional dependency degradation rules.
- Added explicit error category model.
- Added first-class text, Telegram, and JSON rendering separation.
- Added cron locking and partial execution model.
- Added secret lifecycle handling rules.
- Added filesystem TOCTOU mitigation guidance.
- Added compatibility guarantees for CLI, exit codes, config, and JSON.
- Added `schemas/mrrf1.schema.json` as the authoritative JSON Schema Draft 2020-12 contract.
- Added MRRF1 JSON examples for healthy, warning, unavailable, timeout, aggregate, and invalid cases.
- Added the lockfile metadata appendix with exact diagnostic metadata and concurrency policy.
- Completed final architecture validation and approval gate.
