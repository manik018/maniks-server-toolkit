#!/usr/bin/env bash
# MST website module coordinator.

if [[ -n "${MST_WEBSITE_INSPECTOR_LOADED:-}" ]]; then
    return
fi
readonly MST_WEBSITE_INSPECTOR_LOADED=1

# shellcheck source=inspectors/website/common.sh
source "${MST_INSPECTOR_DIR}/website/common.sh"

# Collect one website target without letting failures stop the module.
mst_website_run_collector() {
    local website_index="${1:?website index required}"
    local name="${2:?name required}"
    local url="${3:?url required}"
    local expected_status="${4:?expected status required}"
    local timeout_seconds="${5:?timeout required}"
    local follow_redirects="${6:?follow redirects required}"
    local enabled="${7:?enabled required}"
    local upper_id="${website_index}"
    local record_var="MST_WEBSITE_${upper_id}_RECORD"
    local details_var="MST_WEBSITE_${upper_id}_DETAILS"
    local errors_var="MST_WEBSITE_${upper_id}_ERRORS"
    local rows_var="MST_WEBSITE_${upper_id}_ROWS"
    local record_json
    local -n status_ref="MST_WEBSITE_RECORD_STATUSES"
    local -n severity_ref="MST_WEBSITE_RECORD_SEVERITIES"
    local -n record_jsons_ref="MST_WEBSITE_RECORD_JSONS"
    local -n titles_ref="MST_WEBSITE_SECTION_TITLES"

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

    if ! mst_website_collect_target "${website_index}" "${name}" "${url}" "${expected_status}" "${timeout_seconds}" "${follow_redirects}" "${enabled}" "${record_var}" "${details_var}" "${errors_var}" "${rows_var}"; then
        mst_website_build_internal_failure_record "${website_index}" "${name}" "${record_var}" "${details_var}" "${errors_var}" "Collector execution failed unexpectedly."
    fi

    record_json="$(mst_mrrf_record_json "${record_var}" "${details_var}" "${errors_var}")"
    record_jsons_ref+=("${record_json}")
    status_ref+=("${record_ref[status]}")
    severity_ref+=("${record_ref[severity]}")
    titles_ref+=("${name}")
}

# Collect the full website report and expose the aggregate MRRF1 document.
mst_website_collect_report() {
    local generated_at hostname report_status report_severity report_risk report_exit_code report_json
    local module_summary_json
    local website_index name url expected_status timeout_seconds follow_redirects enabled

    declare -ga MST_WEBSITE_RECORD_JSONS=()
    declare -ga MST_WEBSITE_RECORD_STATUSES=()
    declare -ga MST_WEBSITE_RECORD_SEVERITIES=()
    declare -ga MST_WEBSITE_SECTION_TITLES=()
    declare -ga MST_WEBSITE_SECTION_RECORDS=()
    declare -ga MST_WEBSITE_SECTION_ROWS=()

    mst_website_init_defaults
    website_index=0
    while IFS='|' read -r name url expected_status timeout_seconds follow_redirects enabled; do
        [[ -n "${name}" ]] || continue
        website_index=$(( website_index + 1 ))
        mst_website_run_collector "${website_index}" "${name}" "${url}" "${expected_status}" "${timeout_seconds}" "${follow_redirects}" "${enabled}"
        MST_WEBSITE_SECTION_RECORDS+=("MST_WEBSITE_${website_index}_RECORD")
        MST_WEBSITE_SECTION_ROWS+=("MST_WEBSITE_${website_index}_ROWS")
    done < <(mst_website_targets_catalog)

    generated_at="$(mst_mrrf_now_utc)"
    hostname="$(mst_website_detect_hostname)"
    if [[ "${#MST_WEBSITE_RECORD_STATUSES[@]}" -eq 0 ]]; then
        report_status="unknown"
        report_severity="unknown"
        report_exit_code="${MST_EXIT_PARTIAL}"
    else
        report_status="$(mst_website_worst_status MST_WEBSITE_RECORD_STATUSES)"
        report_severity="$(mst_website_worst_severity MST_WEBSITE_RECORD_SEVERITIES)"
        report_exit_code="$(mst_website_report_exit_code MST_WEBSITE_RECORD_STATUSES)"
    fi
    report_risk="$(mst_mrrf_risk_level_for_status "${report_status}")"
    module_summary_json="$(mst_website_module_summary_json "website" "${#MST_WEBSITE_RECORD_JSONS[@]}" "${report_status}" "${report_severity}")"

    report_json="$(printf '{"schema_version":1,"document_type":"report","toolkit":"mst","toolkit_version":"%s","command":"website","generated_at":"%s","host":{"hostname":"%s"},"records":[%s],"aggregate":{"record_count":%s,"overall_status":"%s","overall_severity":"%s","overall_score":null,"risk_level":"%s","module_summaries":[%s]},"exit_code":%s}' \
        "$(mst_mrrf_json_escape "${MST_VERSION}")" \
        "$(mst_mrrf_json_escape "${generated_at}")" \
        "$(mst_mrrf_json_escape "${hostname}")" \
        "$(IFS=,; printf '%s' "${MST_WEBSITE_RECORD_JSONS[*]}")" \
        "${#MST_WEBSITE_RECORD_JSONS[@]}" \
        "$(mst_mrrf_json_escape "${report_status}")" \
        "$(mst_mrrf_json_escape "${report_severity}")" \
        "$(mst_mrrf_json_escape "${report_risk}")" \
        "${module_summary_json}" \
        "${report_exit_code}")"

    export MST_WEBSITE_REPORT_JSON="${report_json}"
    export MST_WEBSITE_REPORT_STATUS="${report_status}"
    export MST_WEBSITE_REPORT_SEVERITY="${report_severity}"
    export MST_WEBSITE_REPORT_EXIT_CODE="${report_exit_code}"
}
