# Lockfile Metadata Appendix

This appendix defines the exact runtime locking contract for cron-safe and manually safe MST execution.

## Locking Principle

`flock` state is authoritative. Metadata is diagnostic only.

The toolkit must never:

- treat metadata as proof of a live lock
- kill another process based on metadata
- delete a lock merely because a PID appears absent

## Canonical Paths

Lock directory:

- `/var/lib/mst/locks`

Authoritative lock files:

- `/var/lib/mst/locks/report.lock`
- `/var/lib/mst/locks/alert-check.lock`
- `/var/lib/mst/locks/doctor.lock`

Diagnostic metadata files:

- `/var/lib/mst/locks/report.lock.json`
- `/var/lib/mst/locks/alert-check.lock.json`
- `/var/lib/mst/locks/doctor.lock.json`

Temporary metadata staging files:

- `/var/lib/mst/locks/*.lock.json.tmp.*`

## Ownership and Permissions

- owner: `root:root` for cron-created lock paths
- directory mode: `0750`
- lock file mode: `0640`
- metadata file mode: `0640`
- secure process umask: `027`

No lock path may be world-writable.

## Open Mode and Lock Type

- open mode: read-write create if absent
- lock type: exclusive advisory lock
- acquisition behavior: non-blocking for cron jobs, bounded-wait optional for manual commands

## Command Lock Policy

Separate locks:

- `report`
- `alert-check`
- `doctor`

No dedicated lock for lightweight read-only manual commands such as `health`, unless later proven necessary.

Shared lock policy:

- `report` and `alert-check` are separate locks but must also respect a shared execution-family policy:
  - `alert-check` must decline to run if `report.lock` is actively held
  - `report` must decline to run if `alert-check.lock` is actively held

Reason:

- they overlap operationally and can duplicate notification paths

`doctor` is isolated because it is diagnostic and should not block normal inspection unless it directly conflicts with the same lock namespace in a future revision.

## Timeout Behavior

Cron jobs:

- non-blocking lock attempt
- if lock unavailable, exit immediately with non-fatal status

Manual commands that use locks:

- default bounded wait of `0` seconds unless future CLI policy adds a wait option

## Already-Locked Behavior

If lock acquisition fails because another live process holds the lock:

- exit cleanly
- write a local log entry
- do not send Telegram
- do not treat this as stale-lock evidence

## Metadata Contract

Metadata is written only after successful `flock` acquisition.

If metadata write fails:

- keep the authoritative flock-held execution running
- write a sanitized log entry if possible
- never release a valid lock purely because metadata could not be written

## Metadata Format

Metadata is JSON, not shell text.

Required fields:

- `schema_version`
- `run_id`
- `pid`
- `uid`
- `username`
- `command`
- `trigger`
- `hostname`
- `started_at`
- `toolkit_version`

Optional field:

- `lock_name`

### Field Rules

- `schema_version`: integer `1`
- `run_id`: sanitized unique run identifier, max `64`
- `pid`: non-negative integer
- `uid`: non-negative integer
- `username`: max `64`, no control characters
- `command`: one of `report|alert-check|doctor`
- `trigger`: one of `cron|manual`
- `hostname`: max `253`, hostname-safe format
- `started_at`: RFC 3339 UTC timestamp
- `toolkit_version`: max `64`, no control characters
- `lock_name`: optional short identifier

Security requirements:

- no secrets
- no Telegram token
- no chat ID
- no environment dump
- no raw command arguments containing secrets
- bounded metadata length

## Atomic Metadata Write

Metadata must be written by:

1. creating a temporary MST-owned file in the same lock directory
2. writing complete JSON
3. fsync behavior if implementation later chooses to support it
4. atomic rename into place

No symlink following is permitted for metadata writes.

## Stale Lock Semantics

Stale metadata does not imply a stale authoritative lock.

Important clarification:

- PID-file-only locking is forbidden
- stale metadata file alone is not a reason to remove any lock
- after crash or reboot, a stale metadata file may remain
- `flock` correctness must never depend on metadata correctness

Why PID-file-only locking is forbidden:

- PID reuse risk
- TOCTOU race on PID inspection
- inability to prove lock ownership safely
- crash cleanup ambiguity

## Process Crash Behavior

If a process crashes:

- kernel releases the advisory flock when the file descriptor closes
- metadata file may remain
- next execution may overwrite metadata only after acquiring a new flock

## Reboot Behavior

After reboot:

- no prior advisory flock survives
- metadata files may remain on disk
- new execution may proceed after fresh lock acquisition
- implementation may refresh or replace diagnostic metadata after acquiring the new lock

## Manual and Cron Concurrency Behavior

Manual and cron invocations obey the same authoritative flock rules.

Manual runs are not privileged over cron runs.
Cron runs are not privileged over manual runs.

## Concurrency Truth Table

| Scenario | Expected Behavior |
|---|---|
| cron report vs cron report | Second run exits immediately; no duplicate report; log only |
| cron report vs manual report | Manual run exits immediately if cron run holds `report.lock`; no Telegram side effect |
| manual report vs manual report | Second run exits immediately; first run remains authoritative |
| report vs doctor | Allowed concurrently because they use separate locks |
| report vs health | Allowed concurrently; health has no report-family lock |
| alert check vs report | Second run exits immediately because report and alert-check are mutually exclusive by policy |
| process crash | Authoritative flock released by kernel; metadata may remain |
| system reboot | No lock survives reboot; metadata may remain diagnostic only |

## Consistency With Zero-Risk Security Policy

This locking design remains compliant because:

- it does not rely on killing processes
- it does not use world-writable paths
- it writes only MST-owned paths
- it contains no secret-bearing metadata
- it does not require remote coordination
- lock correctness does not depend on unsafe PID-file logic

