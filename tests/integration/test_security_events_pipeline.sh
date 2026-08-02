#!/usr/bin/env bash
# Validate the security events command, persistence, and zero-argument discovery.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/security-events-pipeline"
STATE_DIR="${TMP_DIR}/state"

rm -rf -- "${TMP_DIR}"
mkdir -p -- "${TMP_DIR}/log" "${STATE_DIR}" "${TMP_DIR}/locks"
trap 'rm -rf -- "${TMP_DIR}"' EXIT INT TERM

source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"

mst_fs_validate_runtime_directory() {
    local path="${1:?path required}"
    [[ "${path}" == "${TMP_DIR}" || "${path}" == "${TMP_DIR}"/* ]] || return 1
    [[ ! -L "${path}" ]] || return 1
    printf '%s' "${path}"
}

mst_fs_validate_runtime_file_path() {
    local path="${1:?path required}"
    [[ "${path}" == "${TMP_DIR}"/* ]] || return 1
    [[ ! -L "${path}" ]] || return 1
    printf '%s' "${path}"
}

export MST_LOG_DIR="${TMP_DIR}/log"
export MST_STATE_DIR="${STATE_DIR}"
export MST_LOCK_DIR="${TMP_DIR}/locks"
export MST_LOG_FILE="${TMP_DIR}/log/mst.log"
export MST_OUTPUT_MODE="text"
export MST_COLOR_MODE="never"
export MST_LOG_LEVEL="ERROR"
export MST_SECURITY_EVENTS_ENABLED="true"
export MST_ALERTS_ENABLED="false"
export MST_ALERT_MODULES="all"
mst_logging_init

mst_command_run_with_lock() {
    local _lock_name="${1:?lock name required}"
    local command_fn="${2:?command function required}"
    shift 2
    "${command_fn}" "$@"
}

source "${ROOT_DIR}/commands/security_events.sh"
mst_command_security_events_run > "${TMP_DIR}/security-events.out"
[[ -f "${STATE_DIR}/reports/security_events.mrrf1.json" ]] || exit 1
grep -q '"command":"security_events"' "${STATE_DIR}/reports/security_events.mrrf1.json" || exit 1
grep -q '"check":"module_status"' "${STATE_DIR}/reports/security_events.mrrf1.json" || exit 1
grep -q '"status":"ok"' "${STATE_DIR}/reports/security_events.mrrf1.json" || exit 1

source "${ROOT_DIR}/commands/report.sh"
report_status=0
mst_command_report_run > "${TMP_DIR}/report.out" || report_status=$?
[[ "${report_status}" -eq "${MST_EXIT_PARTIAL}" ]] || exit 1
grep -q 'Security Events' "${TMP_DIR}/report.out" || exit 1

source "${ROOT_DIR}/commands/alert.sh"
alert_status=0
mst_command_alert_execute > "${TMP_DIR}/alert.out" || alert_status=$?
[[ "${alert_status}" -eq "${MST_EXIT_PARTIAL}" ]] || exit 1
[[ "$(mst_report_module_catalog | wc -l | tr -d ' ')" == "7" ]] || exit 1
[[ "$(mst_alert_module_catalog | wc -l | tr -d ' ')" == "7" ]] || exit 1

printf 'test_security_events_pipeline.sh passed.\n'
