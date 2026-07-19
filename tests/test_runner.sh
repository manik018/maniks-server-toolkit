#!/usr/bin/env bash
# Run the MST foundation automated tests.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MST_TEST_TMP_ROOT="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}"
MST_TEST_UNIT_DIR="${MST_TEST_UNIT_DIR:-${ROOT_DIR}/tests/unit}"
MST_TEST_INTEGRATION_DIR="${MST_TEST_INTEGRATION_DIR:-${ROOT_DIR}/tests/integration}"

export LC_ALL=C
export TZ=UTC
export MST_TEST_TMP_ROOT

case "${MST_TEST_TMP_ROOT}" in
    "${ROOT_DIR}/.test-tmp"|"${ROOT_DIR}/.test-tmp/"*)
        ;;
    *)
        printf 'Refusing to clean unsafe test temporary root: %s\n' "${MST_TEST_TMP_ROOT}" >&2
        exit 1
        ;;
esac

mst_runner_cleanup_tmp() {
    if [[ -e "${MST_TEST_TMP_ROOT}" ]]; then
        rm -rf -- "${MST_TEST_TMP_ROOT}" || {
            printf 'Failed to clean test temporary root: %s\n' "${MST_TEST_TMP_ROOT}" >&2
            return 1
        }
    fi
}

mst_runner_reset_environment() {
    unset MST_CONFIG_FILE MST_LOG_DIR MST_LOG_FILE MST_STATE_DIR MST_LOCK_DIR
    unset MST_HEALTH_REPORT_JSON MST_SERVICES_REPORT_JSON MST_SECURITY_REPORT_JSON
    unset MST_WEBSITE_REPORT_JSON MST_WORDPRESS_REPORT_JSON MST_BACKUP_REPORT_JSON
    unset MST_ALERT_STATE_FILE MST_ALERT_TOTAL_EVENTS MST_ALERT_DELIVERABLE_EVENTS
    unset MST_ALERT_SUPPRESSED_EVENTS MST_ALERT_RECOVERY_EVENTS MST_ALERT_INVALID_EVENTS
    unset MST_ALERT_STATE_SAVE_ERROR MST_ALERT_STATE_ERROR_KIND MST_ALERT_STATE_TARGET_KIND
    unset MST_ALERT_STATE_PERSISTENCE_AVAILABLE
}

mst_runner_on_exit() {
    local status=$?
    mst_runner_cleanup_tmp || status=1
    exit "${status}"
}

trap mst_runner_on_exit EXIT INT TERM

mst_runner_cleanup_tmp

for test_file in \
    "${MST_TEST_UNIT_DIR}/"*.sh \
    "${MST_TEST_INTEGRATION_DIR}/"*.sh
do
    [[ -e "${test_file}" ]] || continue
    mst_runner_cleanup_tmp
    mst_runner_reset_environment
    bash "${test_file}"
done

printf 'Foundation test suite completed.\n'
