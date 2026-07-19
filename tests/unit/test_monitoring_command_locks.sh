#!/usr/bin/env bash
# Validate that top-level monitoring commands use the runtime lock wrapper.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
mst_runtime_init

# shellcheck source=commands/health.sh
source "${ROOT_DIR}/commands/health.sh"
# shellcheck source=commands/report.sh
source "${ROOT_DIR}/commands/report.sh"
# shellcheck source=commands/alert.sh
source "${ROOT_DIR}/commands/alert.sh"

export MST_OUTPUT_MODE="text"
export MST_ALERTS_ENABLED="true"
export MST_ALERT_ON_WARNING="true"
export MST_ALERT_ON_ERROR="true"
export MST_ALERT_ON_UNAVAILABLE="true"
export MST_ALERT_ON_UNKNOWN="true"
export MST_ALERT_MODULES="all"
export MST_ALERT_COOLDOWN_SECONDS="3600"
export MST_ALERT_RECOVERY_ENABLED="true"
export MST_ALERT_REPEAT_ENABLED="false"
export MST_ALERT_REPEAT_INTERVAL_SECONDS="21600"

LOCK_ACQUIRE_CALLS=0
LOCK_RELEASE_CALLS=0
LOCK_METADATA_CALLS=0
LOCK_FAIL=false
LAST_LOCK_NAME=""
WARNING_OUTPUT=""
HEALTH_EXEC_CALLS=0
REPORT_EXEC_CALLS=0
ALERT_EXEC_CALLS=0

reset_lock_fixture() {
    LOCK_ACQUIRE_CALLS=0
    LOCK_RELEASE_CALLS=0
    LOCK_METADATA_CALLS=0
    LOCK_FAIL=false
    LAST_LOCK_NAME=""
    WARNING_OUTPUT=""
    HEALTH_EXEC_CALLS=0
    REPORT_EXEC_CALLS=0
    ALERT_EXEC_CALLS=0
}

mst_lock_acquire_nonblocking() {
    LOCK_ACQUIRE_CALLS=$((LOCK_ACQUIRE_CALLS + 1))
    LAST_LOCK_NAME="${1:?lock name required}"
    if [[ "${LOCK_FAIL}" == "true" ]]; then
        return 1
    fi
    return 0
}

mst_lock_write_metadata() {
    LOCK_METADATA_CALLS=$((LOCK_METADATA_CALLS + 1))
    return 0
}

mst_lock_release() {
    LOCK_RELEASE_CALLS=$((LOCK_RELEASE_CALLS + 1))
    return 0
}

mst_warning_block() {
    WARNING_OUTPUT="${1:-}"
}

mst_log() {
    return 0
}

mst_state_save_report() {
    return 0
}

mst_health_collect_report() {
    HEALTH_EXEC_CALLS=$((HEALTH_EXEC_CALLS + 1))
    MST_HEALTH_REPORT_JSON='{}'
    MST_HEALTH_REPORT_EXIT_CODE=0
    export MST_HEALTH_REPORT_JSON MST_HEALTH_REPORT_EXIT_CODE
}

mst_render_health_report_text() {
    return 0
}

mst_report_collect() {
    REPORT_EXEC_CALLS=$((REPORT_EXEC_CALLS + 1))
    MST_REPORT_EXIT_CODE=0
    export MST_REPORT_EXIT_CODE
}

mst_render_report_text() {
    return 0
}

mst_alert_evaluate() {
    ALERT_EXEC_CALLS=$((ALERT_EXEC_CALLS + 1))
    MST_ALERT_EXIT_CODE=0
    export MST_ALERT_EXIT_CODE
}

mst_render_alert_report_text() {
    return 0
}

reset_lock_fixture
mst_command_health_run
[[ "${LOCK_ACQUIRE_CALLS}" -eq 1 ]] || exit 1
[[ "${LOCK_METADATA_CALLS}" -eq 1 ]] || exit 1
[[ "${LOCK_RELEASE_CALLS}" -eq 1 ]] || exit 1
[[ "${LAST_LOCK_NAME}" == "health" ]] || exit 1
[[ "${HEALTH_EXEC_CALLS}" -eq 1 ]] || exit 1

reset_lock_fixture
mst_command_alert_run
[[ "${LOCK_ACQUIRE_CALLS}" -eq 1 ]] || exit 1
[[ "${LOCK_METADATA_CALLS}" -eq 1 ]] || exit 1
[[ "${LOCK_RELEASE_CALLS}" -eq 1 ]] || exit 1
[[ "${LAST_LOCK_NAME}" == "alert" ]] || exit 1
[[ "${ALERT_EXEC_CALLS}" -eq 1 ]] || exit 1

reset_lock_fixture
LOCK_FAIL=true
set +e
mst_command_report_run
report_lock_status=$?
set -e
[[ "${report_lock_status}" -eq "${MST_EXIT_PARTIAL}" ]] || exit 1
[[ "${LOCK_ACQUIRE_CALLS}" -eq 1 ]] || exit 1
[[ "${LOCK_METADATA_CALLS}" -eq 0 ]] || exit 1
[[ "${LOCK_RELEASE_CALLS}" -eq 0 ]] || exit 1
[[ "${REPORT_EXEC_CALLS}" -eq 0 ]] || exit 1
[[ "${LAST_LOCK_NAME}" == "report" ]] || exit 1
[[ "${WARNING_OUTPUT}" == *"Another report execution is already running."* ]] || exit 1

reset_lock_fixture
mst_report_collect() {
    REPORT_EXEC_CALLS=$((REPORT_EXEC_CALLS + 1))
    MST_REPORT_EXIT_CODE="${MST_EXIT_PARTIAL}"
    export MST_REPORT_EXIT_CODE
}
set +e
mst_command_report_run
report_failure_status=$?
set -e
[[ "${report_failure_status}" -eq "${MST_EXIT_PARTIAL}" ]] || exit 1
[[ "${LOCK_ACQUIRE_CALLS}" -eq 1 ]] || exit 1
[[ "${LOCK_METADATA_CALLS}" -eq 1 ]] || exit 1
[[ "${LOCK_RELEASE_CALLS}" -eq 1 ]] || exit 1
[[ "${REPORT_EXEC_CALLS}" -eq 1 ]] || exit 1
[[ "${LAST_LOCK_NAME}" == "report" ]] || exit 1

printf 'test_monitoring_command_locks.sh passed.\n'
