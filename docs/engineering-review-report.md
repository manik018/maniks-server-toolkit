# Engineering Review Report

Date: Friday, July 17, 2026  
Project: Manik's Server Toolkit  
Review mode: Independent Engineering Design Review  
Decision scope: Architecture only, no implementation approval

## Executive Summary

The proposed MST architecture is directionally good on security posture and product scope, but it is not yet robust enough for a 10-year maintenance horizon. The main weaknesses are not in the read-only philosophy. They are in architectural precision, operational contracts, and shell-specific maintainability risk.

The current design has three recurring problems:

1. It defines several abstractions without defining their concrete contracts tightly enough.
2. It introduces more layers than a Bash project may realistically sustain without drift.
3. It leaves critical operational behavior underspecified in places where future contributors will otherwise improvise.

This architecture should not proceed directly to implementation. It needs another design pass focused on simplification, contract hardening, and shell-specific operational realism.

## Strengths

- The product scope is disciplined. A short-lived, no-daemon, read-only CLI is the right foundation for the stated goals.
- The security posture is much stronger than most small monitoring tools because it explicitly rejects remediation, listeners, and telemetry.
- Separating command orchestration from domain inspection is the correct long-term instinct.
- Treating Telegram as a delivery adapter rather than a control surface is the right decision.
- Explicit acknowledgement of `UNKNOWN`, partial failure, and least privilege is strong.
- Installer and uninstaller are treated as first-class architecture topics rather than afterthoughts.
- The release model already assumes signatures/checksums, which is mature.

## Weaknesses

- The architecture is too abstract in several places for a Bash codebase and risks devolving into undocumented conventions.
- The dependency model is stated, but the runtime loading model is not fully reconciled with it.
- The design introduces multiple engines that may not justify their own module boundaries in a shell project.
- The data model is underdefined. “Normalized findings” is referenced repeatedly, but no concrete schema contract exists.
- The privilege model is conceptually correct but operationally incomplete.
- The configuration model is underspecified for multi-target websites and future expansion.
- The testing design is broad but not yet prioritized around what is truly testable in shell.

## Critical Issues

### 1. No formal result schema contract

The architecture repeatedly relies on “normalized findings,” “alert objects,” and “report model” but never defines a canonical shell-safe data format. That is a major design hole.

Why this is critical:

- Every module boundary depends on it.
- Bash has weak native data structures.
- Without a strict contract, contributors will invent incompatible formats.
- Scoring, reporting, alerts, and recommendations will become tightly coupled through ad hoc parsing.

Required change:

- Define one primary internal data contract now.
- Choose exactly one: line-oriented key/value records, sectioned INI-like blocks, JSON via optional renderer boundary only, or TSV records with strict escaping rules.
- Document required escaping, ordering, null handling, unknown handling, and multi-value encoding.

### 2. The architecture is over-layered for Bash

The proposed split of commands, inspectors, multiple engines, and many helper libraries is sound in theory but risks over-engineering in shell. Bash is not a good medium for deep abstraction trees.

Why this is critical:

- Abstractions that are cheap in Go or Python are expensive in shell.
- Contributors will bypass layers when under delivery pressure.
- A design that depends on strict purity across many sourced files is fragile over 300 releases.

Required change:

- Collapse the design into fewer layers:
  - core libraries
  - inspectors
  - presentation/aggregation
  - commands
- Merge `engine-score` and `engine-recommend` into a single policy engine unless a strong independent contract is written.
- Treat alert/report rendering as presentation concerns over a shared report model, not separate “engines” unless necessary.

### 3. Bootstrap and dependency architecture are not aligned

The ADD says dependencies should be explicit and low-coupled, but the current direction still assumes broad runtime sourcing and global function availability.

Why this is critical:

- Hidden dependencies are almost guaranteed in sourced-shell systems unless loading is tightly structured.
- Circular dependency risk becomes real even if the diagram says “no circular dependency.”
- Debugging becomes difficult when function presence depends on load order.

Required change:

- Specify a deterministic load order and a strict import policy.
- Either:
  - use a single curated bootstrap that loads all core libraries and then one command module plus its dependencies, or
  - use a generated manifest of allowed imports.
- Do not leave import behavior to contributor convention.

### 4. Privilege escalation path is underspecified

The design mentions `--as-root-if-needed` and elevated re-entry, but that is a dangerous and underspecified mechanism under the Zero-Risk Security Policy.

Why this is critical:

- Re-execing with elevation is an architectural security boundary.
- It affects config trust, argument trust, environment trust, logging, and temp-file handling.
- Poorly designed privileged re-entry becomes the largest attack surface in the project.

Required change:

- Remove `--as-root-if-needed` from the architecture unless a full privilege transition design is documented.
- Prefer explicit operator guidance: “Run this command with sudo for full visibility.”
- If privileged re-entry remains, it needs a dedicated privilege-transition design section.

### 5. Cron architecture is too coarse

Cron is currently treated as a simple install artifact, but at 1000 servers and 10 years, cron behavior becomes a reliability and safety concern.

Why this is critical:

- Overlapping runs can cause contention and alert storms.
- Long-running checks can stack.
- Cron environment differences will create inconsistent behavior.

Required change:

- Add a run-lock architecture.
- Add per-command execution time ceilings.
- Define cron-safe stdout/stderr behavior.
- Define idempotency and overlap handling.

## Major Issues

### 1. Configuration model needs stronger separation of concerns

The config architecture mixes thresholds, runtime behavior, target inventory, and delivery settings in one conceptual layer.

Recommendation:

- Split configuration into:
  - core runtime
  - target inventory
  - thresholds/policy
  - delivery
  - presentation

### 2. Multi-target architecture is only partially designed

Website monitoring mentions target lists, but the CLI, config, reporting, scoring, and Telegram message budgets are still effectively single-host oriented.

Recommendation:

- Decide now whether MST is:
  - primarily single-host with optional small target lists, or
  - a multi-target inventory tool.
- If multi-target, define result pagination and score aggregation rules now.

### 3. Output contract is too human-first

The ADD mentions future JSON export, but machine-readable output is treated as a future concern rather than a first-class contract.

Recommendation:

- Define `--output text|json` now at the architecture level.
- Make text output a renderer over a stable internal model, not the model itself.

### 4. Installer architecture still assumes filesystem simplicity

The installer is bounded to MST-owned paths, which is good, but the architecture does not yet define upgrade semantics, backup behavior for config changes, or ownership migration behavior.

Recommendation:

- Add explicit upgrade cases:
  - fresh install
  - reinstall over same version
  - upgrade with unchanged config
  - upgrade with deprecated config keys
  - partial broken install recovery

### 5. Uninstaller architecture may conflict with retention expectations

Optional config/data deletion is reasonable, but the design does not define whether report archives, logs, or generated state are considered user data.

Recommendation:

- Classify MST-owned artifacts into:
  - runtime artifacts
  - cached artifacts
  - user-retained artifacts

### 6. Doctor command scope is too open-ended

Doctor is at risk of becoming a god command.

Recommendation:

- Split doctor into categories internally:
  - install checks
  - permissions checks
  - dependency checks
  - optional delivery checks
  - target-specific checks

### 7. Release architecture lacks compatibility policy details

Semantic versioning alone is not enough for a shell tool with config and output consumers.

Recommendation:

- Define compatibility guarantees for:
  - CLI verbs
  - exit codes
  - text output stability
  - JSON output stability
  - config keys
  - report templates

## Minor Issues

- `lib/telemetry-none` is conceptually awkward and should not exist as a placeholder module.
- `assets/` has no clear need yet and may be unnecessary.
- `command.config` is named but not architecturally defined.
- The report engine and recommendation engine naming is slightly inconsistent with the rest of the model.
- The ADD does not define whether temperature checks are Linux-only best effort or contractually supported.
- The service catalog should explicitly define how absent optional services affect scoring.
- `optional Unicode if terminal supports it` is underspecified and may create output inconsistency.

## Nice-to-Have Improvements

- Add an explicit compatibility matrix for Ubuntu 24.04 packages and expected command variants.
- Add a “support envelope” section describing expected max website targets, directory scan sizes, and execution budget.
- Add a “contributor ergonomics” section defining file naming, module skeletons, and review checklists.
- Add a “deprecation architecture” section for config keys and commands.
- Add a “structured event code catalog” for log and doctor messages.

## Security Review

### Strengths

- The architecture is strongly biased toward read-only observation.
- Telegram is intentionally outbound-only.
- The architecture prohibits self-update, remote execution, and automatic remediation.
- Symlink and logging risks are at least recognized explicitly.

### Security Concerns

#### 1. Privileged re-entry is not safe as currently described

The presence of `--as-root-if-needed` is the biggest unresolved security concern in the ADD.

Recommendation:

- Remove it from architecture until fully specified.

#### 2. TOCTOU risk is under-acknowledged

The design mentions canonicalization and ownership checks, but not the time-of-check/time-of-use problem across installer, uninstaller, config reads, and target path inspection.

Recommendation:

- Add a filesystem safety subsection that distinguishes:
  - validation only
  - validation plus open
  - validation plus replace
- Document where TOCTOU cannot be fully eliminated in shell and how to minimize it.

#### 3. Cron can be abused indirectly

Even with MST-owned cron files, overlapping jobs, log flooding, and repeated Telegram failures can become operational abuse vectors.

Recommendation:

- Add lock files, rate limiting, and backoff rules to the cron execution design.

#### 4. Secret handling is still incomplete

Root-owned config is good, but there is no architecture for secret lifecycle during:

- doctor testing
- debug mode
- failed delivery
- process inspection
- backup of config during upgrades

Recommendation:

- Add a dedicated secret-handling architecture subsection.

#### 5. Command execution wrapper needs stricter design

The ADD references `lib/exec`, but does not define enough hard rules.

Recommendation:

- Require all external command execution to pass through one approved wrapper.
- Define:
  - timeout behavior
  - argument array handling
  - stdout/stderr capture rules
  - environment sanitization
  - absolute-path policy for security-sensitive commands

## Simplicity Review

Subsystem simplification opportunities:

- Merge `scoring` and `recommend` into a single policy library unless independent reuse is proven.
- Consider folding `engine-alert` and `engine-report` into presentation/rendering plus policy evaluation rather than standalone engines.
- Remove `assets/` unless an actual asset class exists.
- Remove `lib/telemetry-none` entirely.
- Keep `commands/` and `modules/`, but do not create more sub-layers than Bash can realistically support.

Where splitting more is useful:

- Split `doctor` internally by concern.
- Split `config` into parsing and validation responsibilities if it grows.
- Split filesystem safety from generic validation to keep dangerous path logic isolated.

## Long-Term Maintainability Review

At 1000 servers, 20 contributors, and 300 releases, the architecture would be maintainable only if the following are corrected now:

- a single normalized result schema is defined
- runtime loading is deterministic and explicit
- privilege transitions are simplified or removed
- cron concurrency is designed, not assumed away
- configuration is partitioned by concern
- machine-readable output becomes a first-class contract

Without those changes, the project will likely suffer one or more major refactors within five years.

## Recommended Architectural Changes

1. Define a strict normalized result schema before any implementation resumes.
2. Remove `--as-root-if-needed` from the architecture unless a full privileged re-entry design is added.
3. Simplify the layer model into commands, inspectors, core libraries, and presentation/policy.
4. Replace “many engines” with a smaller policy-and-rendering architecture unless stronger separation is justified.
5. Add a run-lock and timeout architecture for cron-invoked commands.
6. Make machine-readable output an architectural requirement now, not a future extension.
7. Partition configuration into runtime, inventory, policy, delivery, and presentation sections.
8. Define compatibility guarantees for CLI, config keys, exit codes, and output formats.
9. Add a dedicated secret-handling design section.
10. Add an explicit command-execution wrapper specification with security rules.

## Updated Dependency Diagram

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
  `-- json

delivery/
  `-- telegram

Rules:
  commands -> core + inspectors + renderers + delivery
  inspectors -> core only
  delivery -> core only
  renderers -> core only
  core/policy evaluates scores, risk, alerts, and recommendations over normalized inspector results
```

## Final Engineering Approval Decision

REJECTED

## Approval Rationale

The architecture is promising but not yet safe enough to freeze for implementation. It has the right philosophy, but it still lacks enough precision in its internal contracts and includes a few shell-hostile abstractions that would likely force architectural rework later. The next step is not coding. The next step is to revise the ADD around data contracts, privilege model simplification, cron execution safety, and layer simplification, then resubmit for review.

