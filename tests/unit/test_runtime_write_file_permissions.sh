#!/usr/bin/env bash
# Validate runtime-created file metadata normalization.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/runtime-write-file-permissions"
CALLS_FILE="${TMP_DIR}/calls.log"
TARGET_FILE="${TMP_DIR}/health.lock"

rm -rf -- "${TMP_DIR}"
mkdir -p -- "${TMP_DIR}"
trap 'rm -rf -- "${TMP_DIR}"' EXIT INT TERM

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"

chmod() {
    printf 'chmod|%s|%s\n' "${1:?mode required}" "${2:?path required}" >> "${CALLS_FILE}"
    command chmod "$@"
}

chgrp() {
    printf 'chgrp|%s|%s\n' "${1:?group required}" "${2:?path required}" >> "${CALLS_FILE}"
    return 0
}

printf 'lock\n' > "${TARGET_FILE}"
mst_runtime_normalize_write_file "${TARGET_FILE}" 0660

grep -F "chmod|0660|${TARGET_FILE}" "${CALLS_FILE}" >/dev/null || exit 1
grep -F "chgrp|sudo|${TARGET_FILE}" "${CALLS_FILE}" >/dev/null || exit 1

printf 'test_runtime_write_file_permissions.sh passed.\n'
