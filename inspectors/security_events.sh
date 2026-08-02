#!/usr/bin/env bash
# MST security events module coordinator.

if [[ -n "${MST_SECURITY_EVENTS_INSPECTOR_LOADED:-}" ]]; then
    return
fi
readonly MST_SECURITY_EVENTS_INSPECTOR_LOADED=1

# shellcheck source=inspectors/security_events/common.sh
source "${MST_INSPECTOR_DIR}/security_events/common.sh"

mst_security_events_collect_report() {
    local generated_at hostname record_json report_json report_status report_severity report_exit_code report_risk
    declare -gA MST_SECURITY_EVENTS_MODULE_STATUS_RECORD=()
    declare -ga MST_SECURITY_EVENTS_MODULE_STATUS_DETAILS=()
    declare -ga MST_SECURITY_EVENTS_MODULE_STATUS_ERRORS=()

    mst_security_events_collect MST_SECURITY_EVENTS_MODULE_STATUS_RECORD MST_SECURITY_EVENTS_MODULE_STATUS_DETAILS MST_SECURITY_EVENTS_MODULE_STATUS_ERRORS
    record_json="$(mst_mrrf_record_json MST_SECURITY_EVENTS_MODULE_STATUS_RECORD MST_SECURITY_EVENTS_MODULE_STATUS_DETAILS MST_SECURITY_EVENTS_MODULE_STATUS_ERRORS)"
    report_status="${MST_SECURITY_EVENTS_MODULE_STATUS_RECORD[status]}"
    report_severity="${MST_SECURITY_EVENTS_MODULE_STATUS_RECORD[severity]}"
    report_exit_code="${MST_EXIT_OK}"
    [[ "${report_status}" == "ok" ]] || report_exit_code="${MST_EXIT_PARTIAL}"
    report_risk="$(mst_mrrf_risk_level_for_status "${report_status}")"
    generated_at="$(mst_mrrf_now_utc)"
    hostname="$(hostname 2>/dev/null || printf 'localhost')"
    report_json="$(printf '{"schema_version":1,"document_type":"report","toolkit":"mst","toolkit_version":"%s","command":"security_events","generated_at":"%s","host":{"hostname":"%s"},"records":[%s],"aggregate":{"record_count":1,"overall_status":"%s","overall_severity":"%s","overall_score":null,"risk_level":"%s","module_summaries":[{"module":"security_events","record_count":1,"status":"%s","severity":"%s","score":null}]},"exit_code":%s}' \
        "$(mst_mrrf_json_escape "${MST_VERSION}")" "$(mst_mrrf_json_escape "${generated_at}")" "$(mst_mrrf_json_escape "${hostname}")" "${record_json}" \
        "$(mst_mrrf_json_escape "${report_status}")" "$(mst_mrrf_json_escape "${report_severity}")" "$(mst_mrrf_json_escape "${report_risk}")" \
        "$(mst_mrrf_json_escape "${report_status}")" "$(mst_mrrf_json_escape "${report_severity}")" "${report_exit_code}")"

    export MST_SECURITY_EVENTS_REPORT_JSON="${report_json}"
    export MST_SECURITY_EVENTS_REPORT_STATUS="${report_status}"
    export MST_SECURITY_EVENTS_REPORT_SEVERITY="${report_severity}"
    export MST_SECURITY_EVENTS_REPORT_EXIT_CODE="${report_exit_code}"
}
