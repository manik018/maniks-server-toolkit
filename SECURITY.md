# MST Zero-Risk Security Policy

This repository follows the non-negotiable zero-risk security policy for Manik's Server Toolkit.

## Core Rules

- Monitoring is read-only by default.
- MST must not modify non-MST system state during normal runtime.
- Telegram is outbound-only over HTTPS and cannot trigger server actions.
- No daemon, listener, local HTTP server, telemetry, analytics, or remote execution.
- When a check cannot be implemented safely, MST returns `UNKNOWN` or `Unavailable without elevated permission`.

## Prohibited Patterns

- `eval`
- `bash -c` with dynamic or untrusted input
- `curl | bash`
- `curl -k` or `--insecure`
- automatic remediation actions
- self-modifying code
- destructive uninstall behavior outside MST-owned paths

## Security Review Workflow

Before each module is extended, document:

1. Data being read
2. Commands being executed
3. Required privileges
4. Files being accessed
5. Network requests being made
6. Possible risks
7. Mitigations
8. Confirmation that no system state is changed

## Required Checks Before Production Use

- ShellCheck
- unit tests
- permission tests
- secret leakage tests
- symlink attack tests
- command injection tests
- malformed configuration tests
- timeout tests
- failure-mode tests

