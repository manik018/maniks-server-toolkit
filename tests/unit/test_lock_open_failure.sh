#!/usr/bin/env bash
# Validate lock initialization failures do not crash on an unset dynamic fd.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/lock-open-failure"

rm -rf -- "${TMP_DIR}"
mkdir -p -- "${TMP_DIR}/locks/report.lock"
trap 'rm -rf -- "${TMP_DIR}"' EXIT INT TERM

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
mst_runtime_init
export MST_LOCK_DIR="${TMP_DIR}/locks"
export MST_OUTPUT_MODE="text"

mst_fs_validate_runtime_directory() {
    printf '%s' "${MST_LOCK_DIR}"
}

set +e
output="$(mst_command_run_with_lock report true 2>&1)"
status=$?
set -e

[[ "${status}" -eq "${MST_EXIT_PARTIAL}" ]] || exit 1
[[ "${output}" == *"Unable to initialize report lock"* ]] || exit 1
[[ "${output}" != *"MST_LOCK_FD: unbound variable"* ]] || exit 1
[[ "${output}" != *"unbound variable"* ]] || exit 1

printf 'test_lock_open_failure.sh passed.\n'
