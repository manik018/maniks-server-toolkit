#!/usr/bin/env bash
# Run ShellCheck for the MST foundation codebase.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v shellcheck >/dev/null 2>&1; then
    printf 'shellcheck is not installed.\n' >&2
    exit 1
fi

shellcheck \
    "${ROOT_DIR}/mst" \
    "${ROOT_DIR}/install.sh" \
    "${ROOT_DIR}/uninstall.sh" \
    "${ROOT_DIR}/lib/"*.sh \
    "${ROOT_DIR}/commands/"*.sh \
    "${ROOT_DIR}/tests/"*.sh \
    "${ROOT_DIR}/tests/unit/"*.sh \
    "${ROOT_DIR}/tests/integration/"*.sh
