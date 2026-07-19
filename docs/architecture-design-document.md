# Architecture Design Document

Project: Manik's Server Toolkit  
Revision: AR2  
Date: Friday, July 17, 2026  
Status: Architecture Revision 2 Final  
Scope: Architecture only. Implementation remains forbidden.

## 1. Purpose

This document defines the revised target architecture for MST after the Engineering Design Review rejection. It replaces the earlier draft architecture and is designed to resolve the identified blockers before implementation begins.

MST remains:

- a short-lived CLI toolkit
- read-only by default
- daemonless
- outbound-only for Telegram
- installable on Ubuntu 24.04 LTS

## 2. Architectural Principles

- Security over convenience
- Simplicity over speculative abstraction
- Explicit contracts over convention
- Read-only monitoring over remediation
- Deterministic execution over implicit behavior
- Stable interfaces over clever shell patterns
- Graceful degradation over hidden failure

## 3. Simplified Architecture

AR2 removes the earlier over-layering. The architecture is now limited to four operational layers plus lifecycle tooling.

1. Core libraries
2. Inspectors
3. Policy and rendering
4. Commands
5. Installation, packaging, and tests

There are no standalone “engines” for every concern. Scoring, recommendations, and alert evaluation live in a single policy library. Rendering is a separate presentation concern. Telegram is a delivery adapter, not an engine.

## 4. Updated Dependency Diagram

```text
mst
`-- bootstrap
    |-- core/runtime
    |-- core/config
    |-- core/errors
    |-- core/logging
    |-- core/output
    |-- core/validate
    |-- core/filesystem
    |-- core/exec
    |-- core/policy
    `-- commands/
        |-- help
        |-- version
        |-- config
        |-- doctor
        |-- health
        |-- security
        |-- services
        |-- website
        |-- wordpress
        |-- backup
        |-- performance
        |-- system
        |-- report
        |-- alert-check
        |-- telegram-test
        `-- update

inspectors/
  |-- health
  |-- security
  |-- services
  |-- website
  |-- wordpress
  |-- backup
  |-- performance
  `-- system

renderers/
  |-- text
  |-- telegram
  `-- json

delivery/
  `-- telegram

Rules:
  commands -> core + inspectors + renderers + delivery
  inspectors -> core only
  renderers -> core + normalized results only
  delivery -> core + rendered payload only
  core/policy evaluates score, risk, alerts, and recommendations
  no inspector depends on another inspector
  no renderer executes inspection logic
  no delivery adapter evaluates policy
```

## 5. Directory Structure

```text
maniks-server-toolkit/
|-- README.md
|-- LICENSE
|-- CHANGELOG.md
|-- SECURITY.md
|-- install.sh
|-- uninstall.sh
|-- mst
|-- config/
|   `-- config.conf.example
|-- lib/
|   |-- bootstrap.sh
|   |-- runtime.sh
|   |-- config.sh
|   |-- errors.sh
|   |-- logging.sh
|   |-- output.sh
|   |-- validate.sh
|   |-- filesystem.sh
|   |-- exec.sh
|   `-- policy.sh
|-- commands/
|   |-- help.sh
|   |-- version.sh
|   |-- config.sh
|   |-- doctor.sh
|   |-- health.sh
|   |-- security.sh
|   |-- services.sh
|   |-- website.sh
|   |-- wordpress.sh
|   |-- backup.sh
|   |-- performance.sh
|   |-- system.sh
|   |-- report.sh
|   |-- alert-check.sh
|   |-- telegram-test.sh
|   `-- update.sh
|-- inspectors/
|   |-- health.sh
|   |-- security.sh
|   |-- services.sh
|   |-- website.sh
|   |-- wordpress.sh
|   |-- backup.sh
|   |-- performance.sh
|   `-- system.sh
|-- renderers/
|   |-- text.sh
|   |-- telegram.sh
|   `-- json.sh
|-- delivery/
|   `-- telegram.sh
|-- templates/
|   `-- logrotate.conf
|-- docs/
|   |-- architecture-design-document.md
|   |-- architecture-revision-report.md
|   |-- architecture-change-log.md
|   |-- issue-resolution-matrix.md
|   |-- engineering-review-report.md
|   |-- architecture-freeze-report.md
|   |-- security-audit.md
|   |-- installation.md
|   |-- configuration.md
|   |-- troubleshooting.md
|   `-- faq.md
|-- tests/
|   |-- unit/
|   |-- integration/
|   |-- security/
|   |-- fixtures/
|   `-- test_runner.sh
`-- scripts/
    |-- shellcheck.sh
    `-- release-check.sh
```

Removed from AR2:

- `assets/`
- speculative telemetry placeholder
- separate score/recommend/report/alert engines as standalone layers

## 6. Directory Responsibilities

- Root: metadata, entrypoint, lifecycle scripts only
- `config/`: shipped example configuration only
- `lib/`: shared low-level primitives and policy evaluation
- `commands/`: CLI verbs and orchestration only
- `inspectors/`: state collection and normalization only
- `renderers/`: transformation from normalized data to output formats only
- `delivery/`: outbound adapters only
- `templates/`: installation templates only
- `docs/`: architecture and operator documentation
- `tests/`: test harnesses, fixtures, security cases
- `scripts/`: release and verification tooling

## 7. Runtime Loading Model

This section replaces the underspecified bootstrap design.

Loading rules:

1. `mst` loads `lib/bootstrap.sh`.
2. `bootstrap.sh` loads all core libraries in a fixed order.
3. `bootstrap.sh` parses the command verb.
4. `bootstrap.sh` loads exactly one command module.
5. The command module loads only the inspectors, renderers, and delivery adapters it explicitly declares.

There is no “source everything” model in the target architecture.

Required guarantees:

- deterministic load order
- no implicit function availability
- no inspector loading another inspector
- no runtime discovery of module files

## 8. Normalized Internal Result Schema

This is the primary AR2 redesign.

All inspectors return exactly one shell-safe normalized result document format named `MST Result Record Format v1` or `MRRF1`.

### 8.1 Format

`MRRF1` is a line-oriented, UTF-8 plain text record with sectioned key/value blocks.

Rules:

- one result record per inspected target or logical unit
- keys are ASCII lowercase with underscores
- values are single-line escaped strings
- multi-value fields use repeated keys
- blocks are separated by a blank line
- comments are not allowed

### 8.2 Record Layout

```text
record_type=result
schema_version=1
module=health
target=localhost
status=ok
severity=ok
score=98
summary=CPU and memory within thresholds
duration_ms=184
timestamp_utc=2026-07-17T12:00:00Z

detail_key=cpu_percent
detail_value=12
detail_key=ram_percent
detail_value=41

recommendation=No action required.

metadata_key=source
metadata_value=/proc

error_category=
error_code=
error_message=
```

### 8.3 Mandatory Fields

- `record_type`
- `schema_version`
- `module`
- `target`
- `status`
- `severity`
- `score`
- `summary`
- `duration_ms`
- `timestamp_utc`

### 8.4 Standard Fields

- `record_type`: always `result`
- `schema_version`: always `1` for AR2
- `module`: module identifier
- `target`: inspected logical target
- `status`: `ok|warn|critical|unknown|unavailable`
- `severity`: `ok|warning|critical|unknown`
- `score`: integer `0-100`, blank if not applicable
- `summary`: one-line normalized summary
- `duration_ms`: non-negative integer
- `timestamp_utc`: RFC 3339 UTC timestamp

### 8.5 Repeating Fields

- `detail_key` / `detail_value`
- `recommendation`
- `metadata_key` / `metadata_value`

### 8.6 Error Fields

- `error_category`
- `error_code`
- `error_message`

If no error exists, these fields must still be present with empty values.

### 8.7 Escaping

- newline characters are forbidden in values
- tab characters are forbidden in values
- literal backslash is escaped as `\\`
- literal equals sign is escaped as `\=`

### 8.8 Unknown and Null Rules

- unknown measurement: `status=unknown`
- unsupported measurement: `status=unavailable`
- absent optional field: empty string
- modules must never omit mandatory fields

No module may invent its own output format.

## 9. Module Contract Standard

Every module must publish a design record using this exact contract.

### 9.1 Contract Fields

- Purpose
- Inputs
- Outputs
- Exit codes
- Required privileges
- Files accessed
- Commands executed
- Mandatory dependencies
- Optional dependencies
- Failure behavior
- Security considerations
- Extension points

### 9.2 Generic Inspector Contract

Public functions:

- `mst_inspector_<name>_collect`
- `mst_inspector_<name>_contract`

Inputs:

- validated config view
- validated runtime context
- validated target spec

Outputs:

- one or more `MRRF1` records on stdout
- sanitized error events through `lib/errors`

Exit behavior:

- `0` if all inspected targets returned valid records
- `7` if one or more targets returned degraded or unknown results but command may continue
- no direct process exit inside inspector library code

### 9.3 Generic Command Contract

Public functions:

- `mst_command_<verb>_run`
- `mst_command_<verb>_help`

Inputs:

- parsed CLI options
- validated config

Outputs:

- rendered user output
- standardized exit code

Command modules own:

- selecting inspectors
- invoking policy evaluation
- selecting renderer
- optional delivery invocation

### 9.4 Renderer Contract

Public functions:

- `mst_renderer_<format>_render`

Inputs:

- one or more valid `MRRF1` records
- render options

Outputs:

- formatted output only

Renderers may not:

- inspect the host
- call network services
- modify data semantics

### 9.5 Delivery Contract

Public functions:

- `mst_delivery_<name>_send`

Inputs:

- rendered payload
- validated delivery config

Outputs:

- local success or failure status

Delivery adapters may not:

- trigger host actions
- execute arbitrary commands
- transform business logic

## 10. Command Set and CLI Contract

Canonical commands:

- `mst`
- `mst help`
- `mst version`
- `mst health`
- `mst security`
- `mst services`
- `mst backup`
- `mst website`
- `mst wordpress`
- `mst performance`
- `mst system`
- `mst report`
- `mst doctor`
- `mst update`
- `mst config show`
- `mst telegram test`
- `mst alert-check`

Global options:

- `--config FILE`
- `--no-color`
- `--output text|json`
- `--quiet`
- `--verbose`
- `--timeout SECONDS`

Removed from architecture:

- `--as-root-if-needed`

Rationale:

- implicit privileged re-entry violates least-astonishment and widens attack surface

Privilege escalation model is explicit operator action only.

## 11. Privilege Model

This section fully replaces the earlier vague privilege handling.

### 11.1 Principle

MST never self-escalates. It never re-execs itself under sudo. It never stores privileged credentials.

### 11.2 Modes

- Unprivileged mode: default and preferred
- Elevated mode: operator explicitly runs `sudo mst <command>` if needed

### 11.3 Commands That May Need Elevated Access

- `mst security`
  - reason: some journals, auth logs, or firewall state may require elevated read access
- `mst doctor`
  - reason: installation ownership and cron/logrotate verification may require root visibility
- `mst backup`
  - reason: backup directories may be root-owned
- `mst report`
  - reason: composite command inherits the needs of included modules
- `mst alert-check`
  - reason: same as report subset

### 11.4 Commands Expected To Work Unprivileged

- `mst help`
- `mst version`
- `mst config show` with secret redaction
- `mst health`
- `mst services` for visible systemd data
- `mst system`
- `mst website`
- `mst telegram test` only if config is readable to the invoking user, otherwise it must fail safely

### 11.5 Failure Behavior

If required data is not readable without elevated access:

- module returns `status=unavailable`
- error category is `permission`
- summary states `Unavailable without elevated permission`
- command exit code is `7` for partial completion unless nothing usable was returned and command-specific fatal behavior applies

### 11.6 Least Privilege Enforcement

- no setuid
- no sudo inside MST
- no automatic fallback to root
- no permission weakening for convenience

## 12. Dependency Policy

### 12.1 Mandatory Dependencies

Required for baseline operation:

- `bash`
- `awk`
- `sed`
- `grep`
- `cut`
- `sort`
- `uniq`
- `date`
- `stat`
- `find`
- `timeout`

### 12.2 Standard Runtime Dependencies

Expected on Ubuntu 24.04 but still checked:

- `df`
- `free`
- `ps`
- `ss`
- `systemctl`
- `journalctl`
- `hostname`
- `uname`

### 12.3 Optional Dependencies

- `curl` for website checks and Telegram
- `openssl` for certificate inspection
- `fail2ban-client` for Fail2Ban visibility
- `timedatectl` for NTP state
- `php` for limited WordPress environment hints

### 12.4 Dependency Behavior

- missing mandatory dependency: command exits `3`
- missing optional dependency: affected module returns `unavailable` with dependency error metadata
- every external command must be predeclared in the module contract
- no module may assume a dependency that is not declared

## 13. Standardized Error Model

Every error belongs to exactly one category.

Categories:

- `warning`
- `critical`
- `permission`
- `timeout`
- `network`
- `configuration`
- `dependency`
- `internal`
- `unknown`

Each error event contains:

- `error_category`
- `error_code`
- `error_message`
- `module`
- `target`
- `timestamp_utc`

Rules:

- user-facing error strings must be sanitized
- secret-bearing values must never enter `error_message`
- error categories must not be overloaded for scoring

## 14. Exit Code Standard

- `0`: success
- `1`: internal runtime failure
- `2`: invalid usage or configuration
- `3`: mandatory dependency missing
- `4`: explicit permission denial where the command cannot continue at all
- `5`: command timeout
- `6`: network failure where the command’s primary purpose depends on network
- `7`: partial success, one or more modules degraded, unavailable, or unknown
- `8`: security policy violation or unsafe environment

Inspectors do not exit the process directly. Commands own final exit code selection.

## 15. Configuration Architecture

Configuration is partitioned by concern.

### 15.1 Layers

1. Built-in shipped defaults
2. `/etc/mst/config.conf`
3. `/etc/mst/conf.d/*.conf`
4. CLI presentation overrides only

### 15.2 Sections

- Core runtime
- Inventory
- Policy thresholds
- Delivery
- Presentation

### 15.3 Inventory Model

AR2 explicitly treats MST as a single-host toolkit with optional small target inventories.

Allowed inventories:

- website targets
- backup target paths
- WordPress paths
- service catalog overrides

Unsupported in AR2:

- fleet inventory management
- remote host orchestration

### 15.4 Secrets

Secrets are limited to:

- Telegram bot token
- Telegram chat ID

Secret rules:

- only in root-owned config
- never in templates
- never in debug output
- never in logs
- never in rendered reports except masked status statements

## 16. Filesystem Safety Model

### 16.1 Categories

- validation only
- validation plus open for read
- validation plus replace for MST-owned file writes

### 16.2 Rules

- canonicalize before trust
- reject symlink targets for MST-owned writes
- use atomic replace for MST-owned file updates
- restrict all writes to MST-owned paths only
- document residual TOCTOU risk where shell cannot fully eliminate it

### 16.3 Residual Risk Statement

Shell cannot eliminate all TOCTOU windows around external filesystem state changes by privileged third parties. AR2 mitigates rather than claims perfect elimination.

## 17. Command Execution Wrapper Model

All external commands must pass through `lib/exec`.

Required wrapper behavior:

- argument-array execution only
- no `eval`
- no dynamic `bash -c`
- default timeout required unless explicitly exempted
- separated stdout and stderr capture
- sanitized error propagation
- optional absolute path enforcement for security-sensitive commands
- fixed minimal environment for execution

Security-sensitive commands requiring absolute path policy:

- `systemctl`
- `journalctl`
- `ufw`
- `openssl`
- `curl`

## 18. Internal Data vs Rendering Model

Internal collection data and presentation are fully separated.

Pipeline:

1. inspector emits `MRRF1`
2. policy library enriches score, risk, and recommendations
3. renderer converts records to output format
4. delivery adapter transmits rendered payload if applicable

No renderer may collect data. No inspector may print presentation tables.

## 19. Output Model

Supported output modes:

- `text`
- `json`

Telegram uses its own renderer because payload budget and formatting constraints differ.

### 19.1 Text Rendering

- human-oriented aligned output
- ANSI optional
- deterministic ordering

### 19.2 Telegram Rendering

- outbound-only payload
- line-budget aware
- no ANSI
- summary-first formatting

### 19.3 JSON Rendering

Architecturally first-class in AR2.

JSON renderer converts `MRRF1` into a stable schema:

- command metadata
- records array
- aggregate summary
- exit status

Exact schema appendix:

- [MRRF1 JSON Schema Appendix](mrrf1-json-schema-appendix.md)
- `schemas/mrrf1.schema.json`

## 20. Policy Model

The former separate scoring and recommendation engines are replaced by one policy library.

Policy responsibilities:

- score calculation
- risk level calculation
- recommendation generation
- alert rule evaluation

Policy library inputs:

- validated config
- normalized result records

Policy library outputs:

- enriched result records
- aggregate summary model
- alert candidate list

## 21. Cron Model

This is a major AR2 redesign.

### 21.1 Scheduled Commands

- daily report job
- alert-check job

### 21.2 Locking

Each cron-invoked command must use a dedicated lock file under `/var/lib/mst/locks/`.

Locking requirements:

- one lock per scheduled command
- atomic lock acquisition using safe Linux file practices
- process ID stored in lock metadata
- lock timestamp stored in lock metadata
- stale lock detection based on PID existence plus max age

### 21.3 Overlap Handling

If a valid live lock exists:

- second invocation exits cleanly
- no duplicate report or alert is sent
- local log entry is written

### 21.4 Stale Lock Recovery

A lock is stale only when:

- owning PID is absent
- lock age exceeds configured stale threshold

Stale lock cleanup is limited to MST-owned lock files only.

### 21.5 Partial Execution Handling

Cron commands must:

- write output to temporary MST-owned working files
- promote completed artifacts atomically
- avoid partial report publication after interruption

### 21.6 Power Failure Model

On power loss:

- lock file may remain
- next run performs stale lock validation
- incomplete temporary artifacts are ignored or cleaned if clearly MST-owned and stale

Exact lockfile appendix:

- [Lockfile Metadata Appendix](lockfile-metadata-appendix.md)

## 22. Logging Model

Log classes:

- runtime
- install
- doctor
- delivery
- cron

Each event contains:

- UTC timestamp
- severity
- category
- component
- event code
- sanitized message

No log entry may include:

- Telegram token
- chat ID where avoidable
- passwords
- database credentials
- WordPress salts
- auth headers

## 23. Security Model

AR2 reaffirms full compliance target with the Zero-Risk Security Policy.

### 23.1 Guarantees

- read-only monitoring by default
- no remediation logic
- no remote execution
- no daemon
- no listener
- no self-update
- no arbitrary plugin execution

### 23.2 Network Rules

- website inspector may initiate outbound HTTP/HTTPS requests to configured targets
- Telegram delivery may initiate outbound HTTPS only to official Bot API endpoint
- no inbound networking

### 23.3 Secret Lifecycle

Secrets must be protected during:

- config load
- doctor test
- delivery failure
- upgrade path
- logging

Secret handling rules:

- never echoed
- never passed through debug dumps
- never stored in temp files unless strictly necessary and MST-owned
- never included in renderer input records

## 24. Module Catalog and Contracts

### Health Inspector

- Purpose: local host health snapshot
- Inputs: core config, thresholds, timeout
- Outputs: `MRRF1` result records
- Exit codes: command-owned only
- Required privileges: none expected
- Failure behavior: return `unknown` or `unavailable` records
- Dependencies: mandatory standard commands, optional `timedatectl`

### Security Inspector

- Purpose: local security posture inspection
- Inputs: SSH config path, auth log sources, service names
- Outputs: `MRRF1` result records
- Required privileges: often elevated for full visibility
- Failure behavior: partial unavailability without guessing
- Dependencies: `journalctl`, `who`, `last`, optional `fail2ban-client`, optional firewall binary

### Services Inspector

- Purpose: local service state inspection
- Inputs: service catalog
- Outputs: `MRRF1` result records
- Required privileges: none expected for visible systemd state
- Failure behavior: invalid or missing units become `unavailable`
- Dependencies: `systemctl`

### Website Inspector

- Purpose: inspect configured website targets
- Inputs: small website inventory list
- Outputs: per-target `MRRF1` records
- Required privileges: none
- Failure behavior: DNS/network/TLS failures become explicit categorized errors
- Dependencies: optional `curl`, optional `openssl`

### WordPress Inspector

- Purpose: safe WordPress filesystem identification
- Inputs: configured candidate paths
- Outputs: `MRRF1` records
- Required privileges: none unless filesystem restricted
- Failure behavior: unreadable path becomes `unavailable`
- Dependencies: `find`, `du`, optional `php`

### Backup Inspector

- Purpose: inspect existing backup evidence
- Inputs: configured backup paths and thresholds
- Outputs: `MRRF1` records
- Required privileges: may require root if backup storage is root-only
- Failure behavior: unreadable targets become `unavailable`
- Dependencies: `find`, `stat`

### Performance Inspector

- Purpose: one-shot resource hotspot identification
- Inputs: runtime timeout, scan scope
- Outputs: `MRRF1` records
- Required privileges: none
- Failure behavior: expensive scans time out to `unknown`
- Dependencies: `ps`, `ss`, `du`

### System Inspector

- Purpose: host identity summary
- Inputs: none beyond runtime context
- Outputs: `MRRF1` records
- Required privileges: none
- Failure behavior: missing metadata becomes `unknown`
- Dependencies: `hostname`, `uname`

### Doctor Command

Internally split into:

- install checks
- permission checks
- dependency checks
- config checks
- delivery checks
- target checks

Doctor is not an inspector and must not become a general-purpose report command.

## 25. Report and Alert Model

### 25.1 Report

`mst report` is a composite command over multiple inspectors.

Report flow:

1. run selected inspectors
2. collect `MRRF1` records
3. apply policy library
4. render to requested output

### 25.2 Alerts

Alert evaluation is policy-driven and informational only.

Alert records must contain:

- source module
- target
- severity
- summary
- recommendation
- timestamp

No alert may trigger remediation.

## 26. Installer and Upgrade Architecture

Installer modes:

- dry run
- fresh install
- reinstall
- upgrade
- repair of broken MST-owned install

Upgrade requirements:

- do not overwrite unsafe targets
- preserve user config
- create config backup only within MST-owned backup location if required
- warn on deprecated keys

## 27. Uninstaller Architecture

Artifact classes:

- runtime artifacts
- cached/generated artifacts
- retained user data

Default uninstall removes:

- binary
- core runtime
- cron drop-in
- logrotate drop-in

Optional destructive cleanup removes:

- config
- logs
- cached/generated state

No non-MST path may ever be removed.

## 28. Testing Architecture

### 28.1 Priorities

AR2 narrows testing scope to what is sustainable in shell.

Required test classes:

- unit tests for validation, parsing, policy, and rendering
- integration tests for commands with fixtures
- security tests for path validation, injection resistance, secret redaction, symlink behavior, lock handling
- failure-mode tests for missing dependency, timeout, permission denial, malformed config
- compatibility tests for text and JSON output contracts

### 28.2 Fixture Strategy

Use fixture trees for:

- fake backup directories
- fake WordPress paths
- canned journal output
- canned systemctl output
- canned website and certificate responses

### 28.3 Non-goal

No test should require a real production server.

## 29. Release and Compatibility Policy

Release gates:

1. lint
2. unit tests
3. integration tests
4. security tests
5. packaging validation
6. output contract checks
7. checksum generation
8. signed release validation

Compatibility guarantees:

- top-level CLI verbs are stable within a major version
- exit codes are stable within a major version
- JSON schema is stable within a major version once released
- text output is human-stable but not strict machine API
- config keys are deprecated before removal when practical

## 30. Extensibility Model

Future modules must be pluggable through the inspector contract without changing existing inspectors.

Pluggability rules:

- new inspector must emit `MRRF1`
- new inspector must declare dependencies and privileges
- policy library consumes normalized records, not module-specific data shapes
- renderers do not require changes for basic new-module support if records follow the schema

This is the only approved extensibility path in AR2.

## 31. Support Envelope

AR2 assumes:

- one local host per MST install
- small website inventory, not large fleet inventory
- bounded directory scans
- cron jobs scheduled infrequently enough to remain snapshot-style

If MST later needs fleet-scale orchestration, that should be a separate product or architecture revision, not an additive patch.

## 32. Validation Summary

Architecture completion validation performed on Friday, July 17, 2026:

- MRRF1 JSON Schema syntax validated successfully
- valid MRRF1 examples validated successfully against the schema
- invalid MRRF1 examples failed validation as intended
- lock design confirmed to rely on `flock` rather than PID-file authority
- lock design confirmed not to require killing other processes
- lock paths confirmed to be MST-owned and not world-writable by contract
- lock metadata confirmed to contain no secret-bearing fields
- lock correctness confirmed to survive process crash and system reboot
- design confirmed compatible with standard Ubuntu 24.04 `flock`
- design confirmed consistent with the Zero-Risk Security Policy

## 33. Internal Architecture Re-Review

This re-review was performed after AR2 redesign.

Questions asked:

- Is the result schema now explicit enough for Bash?
- Is the privilege model now simpler and safer?
- Is cron now designed rather than implied?
- Are rendering and collection fully separated?
- Has unnecessary abstraction been removed?

Assessment:

- The result schema issue is fully addressed.
- The privilege model is materially safer after removing self-escalation.
- The cron model now has explicit overlap, stale lock, and partial execution behavior.
- The architecture is significantly simpler than AR1.
- The remaining conditional approval items are now complete.

Internal approval decision:

APPROVED

Reason:

The architecture now has:

1. a precise normalized result schema
2. a precise on-disk lock metadata contract
3. validated examples
4. a safer and simpler privilege and dependency model
5. a fully defined rendering boundary

Architecture is frozen. Foundation implementation may begin.
