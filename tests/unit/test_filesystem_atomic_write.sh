#!/usr/bin/env bash
# Validate atomic write argument handling.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/filesystem-atomic"
TARGET_FILE="${TMP_DIR}/state/file.txt"

rm -rf -- "${TMP_DIR}"
mkdir -p -- "${TMP_DIR}/state"
trap 'rm -rf -- "${TMP_DIR}"' EXIT INT TERM

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"

if mst_fs_atomic_write "${TARGET_FILE}" 0640 >/dev/null 2>&1; then
    printf 'atomic write should reject omitted content argument.\n' >&2
    exit 1
fi

mst_fs_atomic_write "${TARGET_FILE}" 0640 ""
[[ -f "${TARGET_FILE}" ]] || exit 1

mst_fs_atomic_write "${TARGET_FILE}" 0640 "hello"
[[ "$(cat -- "${TARGET_FILE}")" == "hello" ]] || exit 1

printf 'test_filesystem_atomic_write.sh passed.\n'
