# Architecture Revision Report

Revision: AR2  
Date: Friday, July 17, 2026

## Objective

Revise the rejected architecture until the major Engineering Review blockers are addressed without implementing features.

## What Changed

- Introduced one mandatory normalized internal result schema: `MRRF1`
- Published the exact MRRF1 JSON Schema appendix and machine-readable schema file
- Removed speculative and shell-hostile layering
- Replaced multiple standalone engines with a smaller policy plus rendering model
- Removed self-escalation and replaced it with an explicit privilege model
- Added a full cron execution and locking model
- Published the exact lockfile metadata appendix for `flock`-based execution control
- Added a strict dependency policy
- Added a standardized error category model
- Made JSON a first-class architectural output mode
- Added a dedicated secret lifecycle and filesystem safety model
- Tightened runtime loading and import behavior

## Design Outcome

AR2 is materially simpler, more explicit, and more secure than the prior architecture. It is better aligned with Bash’s strengths and limitations and is much less likely to force a major refactor within five years.

## Validation Results

- MRRF1 schema syntax validated successfully
- all valid MRRF1 examples passed schema validation
- all invalid MRRF1 examples failed schema validation
- lock design verified to keep `flock` authoritative
- lock design verified not to require process termination
- lock design verified to avoid world-writable lock paths
- lock metadata verified to exclude secrets
- lock design verified to survive crash and reboot scenarios
- design verified to remain compatible with Ubuntu 24.04 `flock`
- design verified to remain consistent with the Zero-Risk Security Policy

## Final Revision Outcome

The remaining conditional acceptance items are complete. AR2 is now ready for final approval.
