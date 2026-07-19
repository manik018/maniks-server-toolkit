#!/usr/bin/env bash
# MST services module coordinator.

if [[ -n "${MST_SERVICES_INSPECTOR_LOADED:-}" ]]; then
    return
fi
readonly MST_SERVICES_INSPECTOR_LOADED=1

# shellcheck source=inspectors/services/common.sh
source "${MST_INSPECTOR_DIR}/services/common.sh"

# Collect one configured service family without letting failures stop the module.
mst_services_run_collector() {
    local service_id="${1:?service id required}"
    local collector_fn="${2:?collector function required}"
    local upper_id="${service_id^^}"
    local record_var="MST_SERVICES_${upper_id}_RECORD"
    local details_var="MST_SERVICES_${upper_id}_DETAILS"
    local errors_var="MST_SERVICES_${upper_id}_ERRORS"
    local rows_var="MST_SERVICES_${upper_id}_ROWS"
    local record_json
    local -n status_ref="MST_SERVICES_RECORD_STATUSES"
    local -n severity_ref="MST_SERVICES_RECORD_SEVERITIES"
    local -n record_jsons_ref="MST_SERVICES_RECORD_JSONS"

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

    if ! "${collector_fn}" "${service_id}" "${record_var}" "${details_var}" "${errors_var}" "${rows_var}"; then
        mst_services_build_internal_failure_record "${service_id}" "${record_var}" "${details_var}" "${errors_var}" "Collector execution failed unexpectedly."
    fi

    record_json="$(mst_mrrf_record_json "${record_var}" "${details_var}" "${errors_var}")"
    record_jsons_ref+=("${record_json}")
    status_ref+=("${record_ref[status]}")
    severity_ref+=("${record_ref[severity]}")
}

# Collect the full services report and expose the aggregate MRRF1 document.
mst_services_collect_report() {
    local generated_at hostname report_status report_severity report_risk report_exit_code report_json
    local module_summary_json
    local service_id

    declare -ga MST_SERVICES_RECORD_JSONS=()
    declare -ga MST_SERVICES_RECORD_STATUSES=()
    declare -ga MST_SERVICES_RECORD_SEVERITIES=()

    mst_services_init_defaults
    while IFS='|' read -r service_id _service_label _candidates; do
        [[ -n "${service_id}" ]] || continue
        mst_services_run_collector "${service_id}" mst_services_collect_service
    done < <(mst_services_service_catalog)

    generated_at="$(mst_mrrf_now_utc)"
    hostname="$(mst_services_detect_hostname)"
    report_status="$(mst_services_worst_status MST_SERVICES_RECORD_STATUSES)"
    report_severity="$(mst_services_worst_severity MST_SERVICES_RECORD_SEVERITIES)"
    report_risk="$(mst_mrrf_risk_level_for_status "${report_status}")"
    report_exit_code="$(mst_services_report_exit_code MST_SERVICES_RECORD_STATUSES)"
    module_summary_json="$(mst_services_module_summary_json "services" "${#MST_SERVICES_RECORD_JSONS[@]}" "${report_status}" "${report_severity}")"

    report_json="$(printf '{"schema_version":1,"document_type":"report","toolkit":"mst","toolkit_version":"%s","command":"services","generated_at":"%s","host":{"hostname":"%s"},"records":[%s],"aggregate":{"record_count":%s,"overall_status":"%s","overall_severity":"%s","overall_score":null,"risk_level":"%s","module_summaries":[%s]},"exit_code":%s}' \
        "$(mst_mrrf_json_escape "${MST_VERSION}")" \
        "$(mst_mrrf_json_escape "${generated_at}")" \
        "$(mst_mrrf_json_escape "${hostname}")" \
        "$(IFS=,; printf '%s' "${MST_SERVICES_RECORD_JSONS[*]}")" \
        "${#MST_SERVICES_RECORD_JSONS[@]}" \
        "$(mst_mrrf_json_escape "${report_status}")" \
        "$(mst_mrrf_json_escape "${report_severity}")" \
        "$(mst_mrrf_json_escape "${report_risk}")" \
        "${module_summary_json}" \
        "${report_exit_code}")"

    export MST_SERVICES_REPORT_JSON="${report_json}"
    export MST_SERVICES_REPORT_STATUS="${report_status}"
    export MST_SERVICES_REPORT_SEVERITY="${report_severity}"
    export MST_SERVICES_REPORT_EXIT_CODE="${report_exit_code}"
}
