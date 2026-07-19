#!/usr/bin/env bash
# Validate CLI registry and stub behavior.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MST_ROOT="${ROOT_DIR}"

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"

if ! mst_is_known_command "doctor"; then
    printf 'doctor command missing from registry.\n' >&2
    exit 1
fi

if mst_is_known_command "unknown-command"; then
    printf 'unknown command should not be in registry.\n' >&2
    exit 1
fi

if [[ "$(mst_command_status "health")" != "implemented" ]]; then
    printf 'health should be implemented.\n' >&2
    exit 1
fi

if [[ "$(mst_command_status "services")" != "implemented" ]]; then
    printf 'services should be implemented.\n' >&2
    exit 1
fi

if [[ "$(mst_command_status "security")" != "implemented" ]]; then
    printf 'security should be implemented.\n' >&2
    exit 1
fi

if [[ "$(mst_command_status "website")" != "implemented" ]]; then
    printf 'website should be implemented.\n' >&2
    exit 1
fi

if [[ "$(mst_command_status "wordpress")" != "implemented" ]]; then
    printf 'wordpress should be implemented.\n' >&2
    exit 1
fi

if [[ "$(mst_command_status "backup")" != "implemented" ]]; then
    printf 'backup should be implemented.\n' >&2
    exit 1
fi

if [[ "$(mst_command_status "report")" != "implemented" ]]; then
    printf 'report should be implemented.\n' >&2
    exit 1
fi

if [[ "$(mst_command_status "telegram")" != "implemented" ]]; then
    printf 'telegram should be implemented.\n' >&2
    exit 1
fi

if [[ "$(mst_command_status "alert")" != "implemented" ]]; then
    printf 'alert should be implemented.\n' >&2
    exit 1
fi

printf 'test_cli.sh passed.\n'
