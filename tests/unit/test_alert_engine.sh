#!/usr/bin/env bash
# Validate alert policy evaluation and state transitions.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_PARENT="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/alert"
TMP_DIR="${TMP_PARENT}/run-$$"
STATE_DIR="${TMP_DIR}/state"
cleanup_test_workspace() {
    rm -rf -- "${TMP_DIR}"
}
trap cleanup_test_workspace EXIT INT TERM
rm -rf -- "${TMP_DIR}"
mkdir -p "${STATE_DIR}"

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/lib/alert.sh"
source "${ROOT_DIR}/renderers/alert_text.sh"

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

mst_fs_atomic_write() {
    local target="${1:?target required}"
    local mode="${2:?mode required}"
    local content="${3:-}"
    local tmp_file
    MST_ALERT_ATOMIC_WRITE_CALLS=$(( MST_ALERT_ATOMIC_WRITE_CALLS + 1 ))
    [[ "${MST_ALERT_ATOMIC_WRITE_FAIL:-false}" != "true" ]] || return 1
    [[ ! -L "${target}" ]] || return 1
    tmp_file="$(mktemp "${target}.tmp.XXXXXX")"
    printf '%s\n' "${content}" > "${tmp_file}"
    chmod "${mode}" "${tmp_file}"
    mv -f -- "${tmp_file}" "${target}"
}

cleanup_alert_state_path() {
    rm -rf "${STATE_DIR}/alerts.state" "${STATE_DIR}/alerts.state".tmp.*
}

reset_alert_config() {
    cleanup_alert_state_path
    export MST_STATE_DIR="${STATE_DIR}"
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
    export MST_ALERT_TEST_NOW_EPOCH="1784289600"
    export MST_ALERT_ATOMIC_WRITE_CALLS=0
    export MST_ALERT_ATOMIC_WRITE_FAIL="false"
    unset MST_HEALTH_REPORT_JSON MST_SERVICES_REPORT_JSON MST_SECURITY_REPORT_JSON MST_WEBSITE_REPORT_JSON MST_WORDPRESS_REPORT_JSON MST_BACKUP_REPORT_JSON
    unset MST_ALERT_STATE_SAVE_ERROR MST_ALERT_STATE_ERROR_KIND MST_ALERT_STATE_TARGET_KIND MST_ALERT_STATE_PERSISTENCE_AVAILABLE
    unset MST_ALERT_MOCK_STATE_TARGET_KIND
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

event_count_by_transition() {
    local wanted="${1:?transition required}"
    local row transition count=0
    for row in "${MST_ALERT_EVENTS[@]:-}"; do
        IFS="${MST_MRRF_FIELD_SEPARATOR}" read -r _event _module _record _current _previous transition _rest <<< "${row}"
        [[ "${transition}" == "${wanted}" ]] && count=$(( count + 1 ))
    done
    printf '%s' "${count}"
}

first_event_field() {
    local field_index="${1:?field required}"
    local row="${MST_ALERT_EVENTS[0]}"
    awk -v sep="${MST_MRRF_FIELD_SEPARATOR}" -v idx="${field_index}" 'BEGIN { FS=sep } { print $idx }' <<< "${row}"
}

event_count_by_reason() {
    local wanted="${1:?reason required}"
    local row reason count=0
    for row in "${MST_ALERT_EVENTS[@]:-}"; do
        reason="$(awk -v sep="${MST_MRRF_FIELD_SEPARATOR}" 'BEGIN { FS=sep } { print $10 }' <<< "${row}")"
        [[ "${reason}" == "${wanted}" ]] && count=$(( count + 1 ))
    done
    printf '%s' "${count}"
}

reset_alert_config
MST_ALERTS_ENABLED="false"
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
mst_alert_evaluate true
[[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "0" ]] || exit 1
[[ "$(event_count_by_transition SUPPRESSED)" -ge 1 ]] || exit 1

reset_alert_config
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|ok|CPU healthy')"
mst_alert_evaluate true
[[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "0" ]] || exit 1
[[ "$(event_count_by_transition UNCHANGED)" == "1" ]] || exit 1

reset_alert_config
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|warn|CPU warning')"
mst_alert_evaluate true
[[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "1" ]] || exit 1
[[ "$(event_count_by_transition NEW)" == "1" ]] || exit 1
[[ "${MST_ALERT_ATOMIC_WRITE_CALLS}" == "1" ]] || exit 1
event_id_first="$(first_event_field 1)"
mst_alert_evaluate true
event_id_second="$(first_event_field 1)"
[[ "${event_id_first}" == "${event_id_second}" ]] || exit 1
[[ "$(event_count_by_transition UNCHANGED)" == "1" ]] || exit 1
[[ "${MST_ALERT_SUPPRESSED_EVENTS}" == "1" ]] || exit 1

reset_alert_config
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
mst_alert_evaluate true
[[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "1" ]] || exit 1
[[ "$(event_count_by_transition NEW)" == "1" ]] || exit 1

reset_alert_config
MST_BACKUP_REPORT_JSON="$(make_report backup 'res_backup.main|backup|main|unavailable|Backup unavailable')"
mst_alert_evaluate true
[[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "1" ]] || exit 1

reset_alert_config
MST_SECURITY_REPORT_JSON="$(make_report security 'res_security.ssh|ssh|ssh|unknown|SSH unknown')"
mst_alert_evaluate true
[[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "1" ]] || exit 1

reset_alert_config
MST_ALERT_ON_WARNING="false"
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|warn|CPU warning')"
mst_alert_evaluate true
[[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "0" ]] || exit 1
[[ "${MST_ALERT_SUPPRESSED_EVENTS}" == "1" ]] || exit 1

reset_alert_config
MST_ALERT_MODULES="backup"
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
MST_BACKUP_REPORT_JSON="$(make_report backup 'res_backup.main|backup|main|critical|Backup failed')"
mst_alert_evaluate true
[[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "1" ]] || exit 1
[[ "$(first_event_field 2)" == "backup" ]] || exit 1

reset_alert_config
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|warn|CPU warning')"
mst_alert_evaluate true
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
mst_alert_evaluate true
[[ "$(event_count_by_transition CHANGED)" == "1" ]] || exit 1
[[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "1" ]] || exit 1

reset_alert_config
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
mst_alert_evaluate true
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|warn|CPU warning')"
mst_alert_evaluate true
[[ "$(event_count_by_transition CHANGED)" == "1" ]] || exit 1

reset_alert_config
MST_ALERT_REPEAT_ENABLED="true"
MST_ALERT_REPEAT_INTERVAL_SECONDS="100"
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
mst_alert_evaluate true
MST_ALERT_TEST_NOW_EPOCH="1784289650"
mst_alert_evaluate true
[[ "$(event_count_by_transition UNCHANGED)" == "1" ]] || exit 1
MST_ALERT_TEST_NOW_EPOCH="1784289801"
mst_alert_evaluate true
[[ "$(event_count_by_transition REPEATED)" == "1" ]] || exit 1

reset_alert_config
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
mst_alert_evaluate true
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|ok|CPU healthy')"
mst_alert_evaluate true
[[ "$(event_count_by_transition RECOVERED)" == "1" ]] || exit 1
[[ "${MST_ALERT_RECOVERY_EVENTS}" == "1" ]] || exit 1

reset_alert_config
MST_ALERT_RECOVERY_ENABLED="false"
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
mst_alert_evaluate true
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|ok|CPU healthy')"
mst_alert_evaluate true
[[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "0" ]] || exit 1
[[ "${MST_ALERT_SUPPRESSED_EVENTS}" == "1" ]] || exit 1

reset_alert_config
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
MST_BACKUP_REPORT_JSON="$(make_report backup 'res_backup.main|backup|main|warn|Backup warning')"
mst_alert_evaluate true
[[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "2" ]] || exit 1

reset_alert_config
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed' '|bad|bad|critical|Missing result')"
mst_alert_evaluate true
[[ "${MST_ALERT_TOTAL_EVENTS}" == "2" ]] || exit 1
[[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "1" ]] || exit 1

reset_alert_config
MST_HEALTH_REPORT_JSON='{"document_type":"record"}'
mst_alert_evaluate true
[[ "${MST_ALERT_INVALID_EVENTS}" -ge 1 ]] || exit 1

reset_alert_config
printf 'malformed-state-row\n' > "${STATE_DIR}/alerts.state"
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
mst_alert_evaluate true
[[ "${MST_ALERT_INVALID_EVENTS}" -ge 1 ]] || exit 1
[[ "$(event_count_by_reason malformed_state)" == "1" ]] || exit 1
[[ "${MST_ALERT_STATE_PERSISTENCE_AVAILABLE}" == "true" ]] || exit 1

reset_alert_config
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
mst_alert_evaluate true
[[ -f "${STATE_DIR}/alerts.state" ]] || exit 1
[[ "$(find "${STATE_DIR}" -name 'alerts.state.tmp.*' | wc -l | tr -d ' ')" == "0" ]] || exit 1

reset_alert_config
ln -s "${STATE_DIR}/other.state" "${STATE_DIR}/alerts.state" 2>/dev/null || printf 'not a symlink' > "${STATE_DIR}/alerts.state"
if [[ -L "${STATE_DIR}/alerts.state" ]]; then
    MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
    mst_alert_evaluate true
    [[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "1" ]] || exit 1
    [[ "${MST_ALERT_ATOMIC_WRITE_CALLS}" == "0" ]] || exit 1
    [[ "$(event_count_by_reason invalid_state_target)" == "1" ]] || exit 1
    [[ "$(event_count_by_reason state_persistence_unavailable)" == "1" ]] || exit 1
fi

reset_alert_config
mkdir "${STATE_DIR}/alerts.state"
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
mst_alert_evaluate true
[[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "1" ]] || exit 1
[[ "${MST_ALERT_ATOMIC_WRITE_CALLS}" == "0" ]] || exit 1
[[ -d "${STATE_DIR}/alerts.state" ]] || exit 1
[[ "$(event_count_by_reason invalid_state_target)" == "1" ]] || exit 1
[[ "$(event_count_by_reason state_persistence_unavailable)" == "1" ]] || exit 1

reset_alert_config
mkfifo "${STATE_DIR}/alerts.state" 2>/dev/null || :
if [[ -p "${STATE_DIR}/alerts.state" ]]; then
    MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
    mst_alert_evaluate true
    [[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "1" ]] || exit 1
    [[ "${MST_ALERT_ATOMIC_WRITE_CALLS}" == "0" ]] || exit 1
    [[ -p "${STATE_DIR}/alerts.state" ]] || exit 1
    [[ "$(event_count_by_reason invalid_state_target)" == "1" ]] || exit 1
    [[ "$(event_count_by_reason state_persistence_unavailable)" == "1" ]] || exit 1
fi

reset_alert_config
MST_ALERT_ATOMIC_WRITE_FAIL="true"
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
mst_alert_evaluate true
[[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "1" ]] || exit 1
[[ "${MST_ALERT_ATOMIC_WRITE_CALLS}" == "1" ]] || exit 1
[[ "$(event_count_by_reason state_write_failed)" == "1" ]] || exit 1

mst_health_collect_report() {
    printf 'collector should not be called.\n' >&2
    exit 1
}

mst_report_collect() {
    printf 'report engine should not be called.\n' >&2
    exit 1
}

mst_telegram_deliver_message() {
    printf 'telegram should not be called.\n' >&2
    exit 1
}

reset_alert_config
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
mst_alert_evaluate true
rendered="$(mst_render_alert_report_text)"
[[ "${rendered}" == *"Alert Decisions"* ]] || exit 1
[[ "${rendered}" == *"Deliverable"* ]] || exit 1

reset_alert_config
mkdir "${STATE_DIR}/alerts.state"
MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
mst_alert_evaluate true
rendered="$(mst_render_alert_report_text)"
[[ "${rendered}" == *"Alert state persistence is unavailable"* ]] || exit 1

eval "$(declare -f mst_alert_state_target_kind | sed '1s/mst_alert_state_target_kind/mst_alert_state_target_kind_original/')"

mst_alert_state_target_kind() {
    printf '%s' "${MST_ALERT_MOCK_STATE_TARGET_KIND:-special}"
}

for mocked_kind in socket block_device character_device; do
    reset_alert_config
    export MST_ALERT_MOCK_STATE_TARGET_KIND="${mocked_kind}"
    MST_HEALTH_REPORT_JSON="$(make_report health 'res_health.cpu|cpu|cpu|critical|CPU failed')"
    mst_alert_evaluate true
    [[ "${MST_ALERT_DELIVERABLE_EVENTS}" == "1" ]] || exit 1
    [[ "${MST_ALERT_ATOMIC_WRITE_CALLS}" == "0" ]] || exit 1
    [[ "${MST_ALERT_STATE_TARGET_KIND}" == "${mocked_kind}" ]] || exit 1
    [[ "$(event_count_by_reason invalid_state_target)" == "1" ]] || exit 1
    [[ "$(event_count_by_reason state_persistence_unavailable)" == "1" ]] || exit 1
done

eval "$(declare -f mst_alert_state_target_kind_original | sed '1s/mst_alert_state_target_kind_original/mst_alert_state_target_kind/')"

printf 'test_alert_engine.sh passed.\n'
