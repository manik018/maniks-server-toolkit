#!/usr/bin/env bash
# MST security events module coordinator.

if [[ -n "${MST_SECURITY_EVENTS_INSPECTOR_LOADED:-}" ]]; then
    return
fi
readonly MST_SECURITY_EVENTS_INSPECTOR_LOADED=1

# shellcheck source=inspectors/security_events/common.sh
source "${MST_INSPECTOR_DIR}/security_events/common.sh"

mst_security_events_collect_report() {
    local generated_at hostname report_json report_status report_severity report_exit_code report_risk status severity rank worst_rank
    declare -gA MST_SECURITY_EVENTS_MODULE_STATUS_RECORD=()
    declare -ga MST_SECURITY_EVENTS_MODULE_STATUS_DETAILS=() MST_SECURITY_EVENTS_MODULE_STATUS_ERRORS=()
    declare -ga MST_SECURITY_EVENTS_RECORD_JSONS=() MST_SECURITY_EVENTS_RECORD_STATUSES=() MST_SECURITY_EVENTS_RECORD_SEVERITIES=() MST_SECURITY_EVENTS_RECORD_VARS=()

    mst_security_events_collect MST_SECURITY_EVENTS_MODULE_STATUS_RECORD MST_SECURITY_EVENTS_MODULE_STATUS_DETAILS MST_SECURITY_EVENTS_MODULE_STATUS_ERRORS
    MST_SECURITY_EVENTS_RECORD_JSONS+=("$(mst_mrrf_record_json MST_SECURITY_EVENTS_MODULE_STATUS_RECORD MST_SECURITY_EVENTS_MODULE_STATUS_DETAILS MST_SECURITY_EVENTS_MODULE_STATUS_ERRORS)")
    MST_SECURITY_EVENTS_RECORD_STATUSES+=("${MST_SECURITY_EVENTS_MODULE_STATUS_RECORD[status]}")
    MST_SECURITY_EVENTS_RECORD_SEVERITIES+=("${MST_SECURITY_EVENTS_MODULE_STATUS_RECORD[severity]}")
    MST_SECURITY_EVENTS_RECORD_VARS+=(MST_SECURITY_EVENTS_MODULE_STATUS_RECORD)

    mst_security_events_collect_fail2ban_records MST_SECURITY_EVENTS_FAIL2BAN_RECORD_JSONS MST_SECURITY_EVENTS_FAIL2BAN_RECORD_STATUSES MST_SECURITY_EVENTS_FAIL2BAN_RECORD_SEVERITIES MST_SECURITY_EVENTS_FAIL2BAN_RECORD_VARS
    MST_SECURITY_EVENTS_RECORD_JSONS+=("${MST_SECURITY_EVENTS_FAIL2BAN_RECORD_JSONS[@]}")
    MST_SECURITY_EVENTS_RECORD_STATUSES+=("${MST_SECURITY_EVENTS_FAIL2BAN_RECORD_STATUSES[@]}")
    MST_SECURITY_EVENTS_RECORD_SEVERITIES+=("${MST_SECURITY_EVENTS_FAIL2BAN_RECORD_SEVERITIES[@]}")
    MST_SECURITY_EVENTS_RECORD_VARS+=("${MST_SECURITY_EVENTS_FAIL2BAN_RECORD_VARS[@]}")
    mst_security_events_collect_sudo_record MST_SECURITY_EVENTS_RECORD_JSONS MST_SECURITY_EVENTS_RECORD_STATUSES MST_SECURITY_EVENTS_RECORD_SEVERITIES MST_SECURITY_EVENTS_RECORD_VARS
    mst_security_events_collect_cron_record MST_SECURITY_EVENTS_RECORD_JSONS MST_SECURITY_EVENTS_RECORD_STATUSES MST_SECURITY_EVENTS_RECORD_SEVERITIES MST_SECURITY_EVENTS_RECORD_VARS
    mst_security_events_collect_package_record MST_SECURITY_EVENTS_RECORD_JSONS MST_SECURITY_EVENTS_RECORD_STATUSES MST_SECURITY_EVENTS_RECORD_SEVERITIES MST_SECURITY_EVENTS_RECORD_VARS

    report_status=ok; worst_rank=0
    for status in "${MST_SECURITY_EVENTS_RECORD_STATUSES[@]}"; do
        rank="$(mst_mrrf_status_rank "${status}")"
        if (( rank > worst_rank )); then worst_rank="${rank}"; report_status="${status}"; fi
    done
    report_severity=ok; worst_rank=0
    for severity in "${MST_SECURITY_EVENTS_RECORD_SEVERITIES[@]}"; do
        case "${severity}" in critical) rank=3 ;; unknown) rank=2 ;; warning|warn) rank=1 ;; *) rank=0 ;; esac
        if (( rank > worst_rank )); then worst_rank="${rank}"; report_severity="${severity}"; fi
    done
    report_exit_code="${MST_EXIT_OK}"
    [[ "${report_status}" == "ok" ]] || report_exit_code="${MST_EXIT_PARTIAL}"
    report_risk="$(mst_mrrf_risk_level_for_status "${report_status}")"
    generated_at="$(mst_mrrf_now_utc)"
    hostname="$(hostname 2>/dev/null || printf 'localhost')"
    report_json="$(printf '{"schema_version":1,"document_type":"report","toolkit":"mst","toolkit_version":"%s","command":"security_events","generated_at":"%s","host":{"hostname":"%s"},"records":[%s],"aggregate":{"record_count":%s,"overall_status":"%s","overall_severity":"%s","overall_score":null,"risk_level":"%s","module_summaries":[{"module":"security_events","record_count":%s,"status":"%s","severity":"%s","score":null}]},"exit_code":%s}' \
        "$(mst_mrrf_json_escape "${MST_VERSION}")" "$(mst_mrrf_json_escape "${generated_at}")" "$(mst_mrrf_json_escape "${hostname}")" "$(IFS=,; printf '%s' "${MST_SECURITY_EVENTS_RECORD_JSONS[*]}")" "${#MST_SECURITY_EVENTS_RECORD_JSONS[@]}" \
        "$(mst_mrrf_json_escape "${report_status}")" "$(mst_mrrf_json_escape "${report_severity}")" "$(mst_mrrf_json_escape "${report_risk}")" "${#MST_SECURITY_EVENTS_RECORD_JSONS[@]}" \
        "$(mst_mrrf_json_escape "${report_status}")" "$(mst_mrrf_json_escape "${report_severity}")" "${report_exit_code}")"

    export MST_SECURITY_EVENTS_REPORT_JSON="${report_json}"
    export MST_SECURITY_EVENTS_REPORT_STATUS="${report_status}"
    export MST_SECURITY_EVENTS_REPORT_SEVERITY="${report_severity}"
    export MST_SECURITY_EVENTS_REPORT_EXIT_CODE="${report_exit_code}"
}
