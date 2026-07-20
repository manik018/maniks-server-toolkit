#!/usr/bin/env bash
# Restore executable bits for MST files intended for direct execution.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_executables=(
    "mst"
    "install.sh"
    "uninstall.sh"
    "scripts/mst-daily-report.sh"
    "scripts/release-check.sh"
    "scripts/restore-executable-bits.sh"
    "scripts/shellcheck.sh"
    "tests/test_runner.sh"
)

for relative_path in "${required_executables[@]}"; do
    target="${ROOT_DIR}/${relative_path}"
    if [[ ! -f "${target}" ]] || [[ -L "${target}" ]]; then
        printf 'Cannot restore executable metadata for unsafe or missing file: %s\n' "${relative_path}" >&2
        exit 1
    fi
    chmod 0755 -- "${target}"
done

printf 'MST executable metadata restored.\n'
