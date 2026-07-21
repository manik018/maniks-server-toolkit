#!/usr/bin/env bash
# Validate alert state persistence through the real filesystem writer.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/alert-real-state"
STATE_DIR="${TMP_DIR}/state"

rm -rf -- "${TMP_DIR}"
mkdir -p -- "${STATE_DIR}"
trap 'rm -rf -- "${TMP_DIR}"' EXIT INT TERM

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/lib/alert.sh"

mst_fs_validate_runtime_file_path() {
    local path="${1:?path required}"
    [[ "${path}" == "${STATE_DIR}"/* ]] || return 1
    [[ ! -L "${path}" ]] || return 1
    [[ -e "${path}" && ! -f "${path}" ]] && return 1
    printf '%s' "${path}"
}

mst_fs_validate_runtime_directory() {
    local path="${1:?path required}"
    [[ "${path}" == "${STATE_DIR}" ]] || return 1
    [[ -d "${path}" ]] || return 1
    [[ ! -L "${path}" ]] || return 1
    printf '%s' "${path}"
}

make_report() {
    local command_name="${1:?command required}"
    shift || true
    local records=()
    local record_spec result_id check_name target_name status_name summary_text index=0 worst_status="ok"

    for record_spec in "$@"; do
        index=$(( index + 1 ))
        IFS='|' read -r result_id check_name target_name status_name summary_text <<< "${record_spec}"
        records+=("$(printf '{"result_id":"%s","module":"%s","check":"%s","target":"%s","status":"%s","severity":"%s","score":null,"summary":"%s","details":[],"recommendations":[],"metadata":{"source":["fixture"],"provenance":"fixture","privilege_requirement":"none","contains_sensitive_data":false,"redactions_present":false,"optional_dependencies":[]},"errors":[],"duration_ms":1,"observed_at":"2026-07-18T00:00:00Z"}' "${result_id}" "${command_name}" "${check_name}" "${target_name}" "${status_name}" "${status_name}" "${summary_text}")")
        case "${status_name}" in
            critical) worst_status="critical" ;;
            unavailable) [[ "${worst_status}" != "critical" ]] && worst_status="unavailable" ;;
            unknown) [[ "${worst_status}" != "critical" && "${worst_status}" != "unavailable" ]] && worst_status="unknown" ;;
            warn) [[ "${worst_status}" == "ok" ]] && worst_status="warn" ;;
        esac
    done

    printf '{"schema_version":1,"document_type":"report","toolkit":"mst","toolkit_version":"test","command":"%s","generated_at":"2026-07-18T00:00:00Z","host":{"hostname":"fixture"},"records":[%s],"aggregate":{"record_count":%s,"overall_status":"%s","overall_severity":"%s","overall_score":null,"risk_level":"low","module_summaries":[{"module":"%s","record_count":%s,"status":"%s","severity":"%s","score":null}]},"exit_code":0}' \
        "${command_name}" \
        "$(IFS=,; printf '%s' "${records[*]:-}")" \
        "${#records[@]}" \
        "${worst_status}" \
        "${worst_status}" \
        "${command_name}" \
        "${#records[@]}" \
        "${worst_status}" \
        "${worst_status}"
}

reset_alert_config() {
    rm -f -- "${STATE_DIR}/alerts.state" "${STATE_DIR}/alerts.state".tmp.*
    export MST_STATE_DIR="${STATE_DIR}"
    export MST_ALERTS_ENABLED="true"
    export MST_ALERT_ON_WARNING="true"
    export MST_ALERT_ON_ERROR="true"
    export MST_ALERT_ON_UNAVAILABLE="true"
    export MST_ALERT_ON_UNKNOWN="true"
    export MST_ALERT_MODULES="all"
    export MST_ALERT_MIN_OCCURRENCES_BEFORE_DELIVERY="2"
    export MST_ALERT_COOLDOWN_SECONDS="3600"
    export MST_ALERT_RECOVERY_ENABLED="true"
    export MST_ALERT_REPEAT_ENABLED="false"
    export MST_ALERT_REPEAT_INTERVAL_SECONDS="21600"
    export MST_ALERT_TEST_NOW_EPOCH="1784289600"
    unset MST_HEALTH_REPORT_JSON MST_SERVICES_REPORT_JSON MST_SECURITY_REPORT_JSON MST_WEBSITE_REPORT_JSON MST_WORDPRESS_REPORT_JSON MST_BACKUP_REPORT_JSON
    unset MST_ALERT_STATE_SAVE_ERROR MST_ALERT_STATE_ERROR_KIND MST_ALERT_STATE_TARGET_KIND MST_ALERT_STATE_PERSISTENCE_AVAILABLE
}

reset_alert_config
mst_alert_evaluate true
[[ -f "${STATE_DIR}/alerts.state" ]] || exit 1
[[ "${MST_ALERT_STATE_SAVE_ERROR:-}" == "" ]] || exit 1

reset_alert_config
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|ok|CPU healthy')"
mst_alert_evaluate true
[[ "${MST_ALERT_EXIT_CODE}" == "${MST_EXIT_OK}" ]] || exit 1
[[ "${MST_ALERT_STATE_SAVE_ERROR:-}" == "" ]] || exit 1
[[ -s "${STATE_DIR}/alerts.state" ]] || exit 1

MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
mst_alert_evaluate true
[[ "${MST_ALERT_STATE_SAVE_ERROR:-}" == "" ]] || exit 1
[[ -s "${STATE_DIR}/alerts.state" ]] || exit 1

printf 'test_alert_real_state_write.sh passed.\n'
