#!/usr/bin/env bash
# Validate the flock-based lock helpers.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/locks"
mkdir -p "${TMP_DIR}"

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
mst_runtime_init
export MST_LOCK_DIR="${TMP_DIR}"

mst_fs_validate_runtime_directory() {
    printf '%s' "${TMP_DIR}"
}

mst_fs_validate_runtime_file_path() {
    printf '%s' "${TMP_DIR}/doctor.lock.json"
}

if ! command -v flock >/dev/null 2>&1; then
    printf 'test_locking.sh skipped: flock is unavailable in this host shell.\n'
    exit 0
fi

mst_lock_acquire_nonblocking "doctor"
mst_lock_write_metadata "manual"
[[ -f "${TMP_DIR}/doctor.lock.json" ]] || exit 1
mst_lock_release

printf 'test_locking.sh passed.\n'
