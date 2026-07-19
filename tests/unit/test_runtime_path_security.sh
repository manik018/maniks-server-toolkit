#!/usr/bin/env bash
# Validate rejection of unsafe runtime write paths.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
mst_runtime_init

if mst_fs_validate_runtime_directory "/tmp/mst-unsafe-log" >/dev/null 2>&1; then
    printf 'unsafe log path should be rejected.\n' >&2
    exit 1
fi

if mst_fs_validate_runtime_directory "/tmp/mst-unsafe-locks" >/dev/null 2>&1; then
    printf 'unsafe lock path should be rejected.\n' >&2
    exit 1
fi

printf 'test_runtime_path_security.sh passed.\n'
