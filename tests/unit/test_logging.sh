#!/usr/bin/env bash
# Validate structured logging behavior.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/logging"
mkdir -p "${TMP_DIR}"

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
mst_runtime_init
export MST_LOG_DIR="${TMP_DIR}"
export MST_LOG_FILE="${TMP_DIR}/mst.log"

mst_fs_validate_runtime_write_paths() {
    export MST_LOG_DIR="${TMP_DIR}"
    export MST_STATE_DIR="/var/lib/mst"
    export MST_LOCK_DIR="/var/lib/mst/locks"
    export MST_LOG_FILE="${TMP_DIR}/mst.log"
    return 0
}

mst_logging_init
mst_log INFO test TEST_EVENT "hello world"

grep -q 'level=INFO component=test event=TEST_EVENT' "${TMP_DIR}/mst.log"
printf 'test_logging.sh passed.\n'
