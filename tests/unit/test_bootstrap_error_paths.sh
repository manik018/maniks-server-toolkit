#!/usr/bin/env bash
# Validate pre-bootstrap error paths that run before lib/errors.sh is available.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/bootstrap-error-paths"

rm -rf -- "${TMP_DIR}"
mkdir -p -- "${TMP_DIR}"
trap 'rm -rf -- "${TMP_DIR}"' EXIT INT TERM

valid_output="$(
    env -u MST_ROOT bash -c '
        set -euo pipefail
        root="${1:?root required}"
        # shellcheck source=lib/bootstrap.sh
        source "${root}/lib/bootstrap.sh"
        mst_bootstrap "${root}"
        printf "%s\n" "${MST_ROOT}"
    ' _ "${ROOT_DIR}"
)"
[[ "${valid_output}" == "${ROOT_DIR}" ]] || exit 1

set +e
mismatch_output="$(
    MST_ROOT="${TMP_DIR}/other-root" bash -c '
        set -euo pipefail
        root="${1:?root required}"
        # shellcheck source=lib/bootstrap.sh
        source "${root}/lib/bootstrap.sh"
        mst_bootstrap "${root}"
        printf "BOOTSTRAP_CONTINUED\n"
    ' _ "${ROOT_DIR}" 2>&1
)"
mismatch_status=$?
set -e
[[ "${mismatch_status}" -eq 1 ]] || exit 1
[[ "${mismatch_output}" == *"Runtime root mismatch."* ]] || exit 1
[[ "${mismatch_output}" != *"unbound variable"* ]] || exit 1
[[ "${mismatch_output}" != *"command not found"* ]] || exit 1
[[ "${mismatch_output}" != *"BOOTSTRAP_CONTINUED"* ]] || exit 1

set +e
invalid_output="$(
    env -u MST_ROOT bash -c '
        set -euo pipefail
        root="${1:?root required}"
        invalid_root="${2:?invalid root required}"
        # shellcheck source=lib/bootstrap.sh
        source "${root}/lib/bootstrap.sh"
        mst_bootstrap "${invalid_root}"
        printf "BOOTSTRAP_CONTINUED\n"
    ' _ "${ROOT_DIR}" "${TMP_DIR}/invalid-root" 2>&1
)"
invalid_status=$?
set -e
[[ "${invalid_status}" -eq 1 ]] || exit 1
[[ "${invalid_output}" == *"Invalid runtime root."* ]] || exit 1
[[ "${invalid_output}" != *"unbound variable"* ]] || exit 1
[[ "${invalid_output}" != *"command not found"* ]] || exit 1
[[ "${invalid_output}" != *"BOOTSTRAP_CONTINUED"* ]] || exit 1

printf 'test_bootstrap_error_paths.sh passed.\n'
