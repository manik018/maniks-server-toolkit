#!/usr/bin/env bash
# MST health module coordinator.

if [[ -n "${MST_HEALTH_INSPECTOR_LOADED:-}" ]]; then
    return
fi
readonly MST_HEALTH_INSPECTOR_LOADED=1

# shellcheck source=inspectors/health/common.sh
source "${MST_INSPECTOR_DIR}/health/common.sh"
# shellcheck source=inspectors/health/cpu.sh
source "${MST_INSPECTOR_DIR}/health/cpu.sh"
# shellcheck source=inspectors/health/memory.sh
source "${MST_INSPECTOR_DIR}/health/memory.sh"
# shellcheck source=inspectors/health/disk.sh
source "${MST_INSPECTOR_DIR}/health/disk.sh"
# shellcheck source=inspectors/health/uptime.sh
source "${MST_INSPECTOR_DIR}/health/uptime.sh"
# shellcheck source=inspectors/health/system.sh
source "${MST_INSPECTOR_DIR}/health/system.sh"

# Collect one health collector without letting failures abort the module.
mst_health_run_collector() {
    local collector_id="${1:?collector id required}"
    local collector_fn="${2:?collector function required}"
    local upper_id="${collector_id^^}"
    local record_var="MST_HEALTH_${upper_id}_RECORD"
    local details_var="MST_HEALTH_${upper_id}_DETAILS"
    local errors_var="MST_HEALTH_${upper_id}_ERRORS"
    local rows_var="MST_HEALTH_${upper_id}_ROWS"
    local record_json
    local -n status_ref="MST_HEALTH_RECORD_STATUSES"
    local -n severity_ref="MST_HEALTH_RECORD_SEVERITIES"
    local -n record_jsons_ref="MST_HEALTH_RECORD_JSONS"

    declare -gA "${record_var}"
    declare -g -a "${details_var}" "${errors_var}" "${rows_var}"

    local -n record_ref="${record_var}"
    local -n details_ref="${details_var}"
    local -n errors_ref="${errors_var}"
    local -n rows_ref="${rows_var}"

    record_ref=()
    details_ref=()
    errors_ref=()
    rows_ref=()

    if ! "${collector_fn}" "${record_var}" "${details_var}" "${errors_var}" "${rows_var}"; then
        mst_health_build_internal_failure_record "${collector_id}" "${record_var}" "${details_var}" "${errors_var}" "Collector execution failed unexpectedly."
    fi

    record_json="$(mst_mrrf_record_json "${record_var}" "${details_var}" "${errors_var}")"
    record_jsons_ref+=("${record_json}")
    status_ref+=("${record_ref[status]}")
    severity_ref+=("${record_ref[severity]}")
}

# Collect the full health report and expose the aggregate MRRF1 document.
mst_health_collect_report() {
    local generated_at hostname report_status report_severity report_risk report_exit_code report_json
    local module_summary_json

    declare -ga MST_HEALTH_RECORD_JSONS=()
    declare -ga MST_HEALTH_RECORD_STATUSES=()
    declare -ga MST_HEALTH_RECORD_SEVERITIES=()

    mst_health_run_collector "cpu" mst_health_collect_cpu
    mst_health_run_collector "memory" mst_health_collect_memory
    mst_health_run_collector "disk" mst_health_collect_disk
    mst_health_run_collector "uptime" mst_health_collect_uptime
    mst_health_run_collector "system" mst_health_collect_system

    generated_at="$(mst_mrrf_now_utc)"
    hostname="$(mst_health_detect_hostname)"
    report_status="$(mst_health_worst_status MST_HEALTH_RECORD_STATUSES)"
    report_severity="$(mst_health_worst_severity MST_HEALTH_RECORD_SEVERITIES)"
    report_risk="$(mst_mrrf_risk_level_for_status "${report_status}")"
    report_exit_code="$(mst_health_report_exit_code MST_HEALTH_RECORD_STATUSES)"
    module_summary_json="$(mst_health_module_summary_json "health" "${#MST_HEALTH_RECORD_JSONS[@]}" "${report_status}" "${report_severity}")"

    report_json="$(printf '{"schema_version":1,"document_type":"report","toolkit":"mst","toolkit_version":"%s","command":"health","generated_at":"%s","host":{"hostname":"%s"},"records":[%s],"aggregate":{"record_count":%s,"overall_status":"%s","overall_severity":"%s","overall_score":null,"risk_level":"%s","module_summaries":[%s]},"exit_code":%s}' \
        "$(mst_mrrf_json_escape "${MST_VERSION}")" \
        "$(mst_mrrf_json_escape "${generated_at}")" \
        "$(mst_mrrf_json_escape "${hostname}")" \
        "$(IFS=,; printf '%s' "${MST_HEALTH_RECORD_JSONS[*]}")" \
        "${#MST_HEALTH_RECORD_JSONS[@]}" \
        "$(mst_mrrf_json_escape "${report_status}")" \
        "$(mst_mrrf_json_escape "${report_severity}")" \
        "$(mst_mrrf_json_escape "${report_risk}")" \
        "${module_summary_json}" \
        "${report_exit_code}")"

    export MST_HEALTH_REPORT_JSON="${report_json}"
    export MST_HEALTH_REPORT_STATUS="${report_status}"
    export MST_HEALTH_REPORT_SEVERITY="${report_severity}"
    export MST_HEALTH_REPORT_EXIT_CODE="${report_exit_code}"
}
