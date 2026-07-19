# Architecture Freeze Report

Date: 2026-07-17  
Project: Manik's Server Toolkit  
Decision: Feature implementation remains paused pending architecture approval.

## Freeze Outcome

An Architecture Freeze package has been produced:

- [Architecture Design Document](architecture-design-document.md)
- [Zero-Risk Security Policy](../SECURITY.md)
- [Security Audit](security-audit.md)

## Key Architectural Decisions

- MST remains a short-lived CLI toolkit, never a daemon or listener
- Read-only inspectors are separated from report, alert, scoring, and recommendation engines
- Commands, libraries, inspectors, and engines are split into distinct layers to reduce coupling
- Configuration, logging, output, validation, and command execution are centralized in shared libraries
- Telegram is treated as an outbound-only delivery adapter
- `mst update` is advisory only, not a self-updater

## Architecture Risks Found

- The current repository already contains provisional implementation code before architecture approval
- The current file layout mixes command orchestration and domain inspection inside `modules/`
- The current bootstrap model sources every module up front, which is acceptable for a small shell project but should evolve to explicit command and module registration to keep dependency boundaries visible
- The current repository does not yet contain the `commands/` split defined in the target architecture
- The current repository does not yet contain formal module design records as standalone artifacts

## Required Conformance Work Before Feature Development

1. Restructure the runtime to match the approved directory and layer model.
2. Introduce explicit command modules separate from inspectors and engines.
3. Formalize normalized result schemas for all inspectors.
4. Standardize exit codes, output contracts, and error object handling.
5. Add module design records and test matrix documents.
6. Re-run the security review against the conformed architecture.

## Approval Gate

Coding should not resume until the following are explicitly approved:

- overall system architecture
- dependency model
- CLI contract
- configuration model
- error and exit-code standard
- output standard
- installer and uninstaller model
- testing and release architecture
- security mitigations

## Recommendation

Architecture is now documented well enough for review. The project should remain in freeze state until the ADD is accepted and the implementation plan is rewritten to conform to it.

