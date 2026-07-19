#!/usr/bin/env bash
# MST security module coordinator.

if [[ -n "${MST_SECURITY_INSPECTOR_LOADED:-}" ]]; then
    return
fi
readonly MST_SECURITY_INSPECTOR_LOADED=1

# shellcheck source=inspectors/security/common.sh
source "${MST_INSPECTOR_DIR}/security/common.sh"

# Collect one security check without letting failures stop the module.
mst_security_run_collector() {
    local check_id="${1:?check id required}"
    local collector_fn="${2:?collector function required}"
    local upper_id="${check_id^^}"
    local record_var="MST_SECURITY_${upper_id}_RECORD"
    local details_var="MST_SECURITY_${upper_id}_DETAILS"
    local errors_var="MST_SECURITY_${upper_id}_ERRORS"
    local rows_var="MST_SECURITY_${upper_id}_ROWS"
    local record_json
    local -n status_ref="MST_SECURITY_RECORD_STATUSES"
    local -n severity_ref="MST_SECURITY_RECORD_SEVERITIES"
    local -n record_jsons_ref="MST_SECURITY_RECORD_JSONS"

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

    if ! "${collector_fn}" "${check_id}" "${record_var}" "${details_var}" "${errors_var}" "${rows_var}"; then
        mst_security_build_internal_failure_record "${check_id}" "${record_var}" "${details_var}" "${errors_var}" "Collector execution failed unexpectedly."
    fi

    record_json="$(mst_mrrf_record_json "${record_var}" "${details_var}" "${errors_var}")"
    record_jsons_ref+=("${record_json}")
    status_ref+=("${record_ref[status]}")
    severity_ref+=("${record_ref[severity]}")
}

# Collect the full security report and expose the aggregate MRRF1 document.
mst_security_collect_report() {
    local generated_at hostname report_status report_severity report_risk report_exit_code report_json
    local module_summary_json
    local check_id collector_fn

    declare -ga MST_SECURITY_RECORD_JSONS=()
    declare -ga MST_SECURITY_RECORD_STATUSES=()
    declare -ga MST_SECURITY_RECORD_SEVERITIES=()

    mst_security_init_defaults
    while IFS='|' read -r check_id _label; do
        [[ -n "${check_id}" ]] || continue
        collector_fn="mst_security_collect_${check_id}"
        mst_security_run_collector "${check_id}" "${collector_fn}"
    done < <(mst_security_check_catalog)

    generated_at="$(mst_mrrf_now_utc)"
    hostname="$(mst_security_detect_hostname)"
    report_status="$(mst_security_worst_status MST_SECURITY_RECORD_STATUSES)"
    report_severity="$(mst_security_worst_severity MST_SECURITY_RECORD_SEVERITIES)"
    report_risk="$(mst_mrrf_risk_level_for_status "${report_status}")"
    report_exit_code="$(mst_security_report_exit_code MST_SECURITY_RECORD_STATUSES)"
    module_summary_json="$(mst_security_module_summary_json "security" "${#MST_SECURITY_RECORD_JSONS[@]}" "${report_status}" "${report_severity}")"

    report_json="$(printf '{"schema_version":1,"document_type":"report","toolkit":"mst","toolkit_version":"%s","command":"security","generated_at":"%s","host":{"hostname":"%s"},"records":[%s],"aggregate":{"record_count":%s,"overall_status":"%s","overall_severity":"%s","overall_score":null,"risk_level":"%s","module_summaries":[%s]},"exit_code":%s}' \
        "$(mst_mrrf_json_escape "${MST_VERSION}")" \
        "$(mst_mrrf_json_escape "${generated_at}")" \
        "$(mst_mrrf_json_escape "${hostname}")" \
        "$(IFS=,; printf '%s' "${MST_SECURITY_RECORD_JSONS[*]}")" \
        "${#MST_SECURITY_RECORD_JSONS[@]}" \
        "$(mst_mrrf_json_escape "${report_status}")" \
        "$(mst_mrrf_json_escape "${report_severity}")" \
        "$(mst_mrrf_json_escape "${report_risk}")" \
        "${module_summary_json}" \
        "${report_exit_code}")"

    export MST_SECURITY_REPORT_JSON="${report_json}"
    export MST_SECURITY_REPORT_STATUS="${report_status}"
    export MST_SECURITY_REPORT_SEVERITY="${report_severity}"
    export MST_SECURITY_REPORT_EXIT_CODE="${report_exit_code}"
}
