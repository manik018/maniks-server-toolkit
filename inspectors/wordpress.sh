#!/usr/bin/env bash
# MST WordPress module coordinator.

if [[ -n "${MST_WORDPRESS_INSPECTOR_LOADED:-}" ]]; then
    return
fi
readonly MST_WORDPRESS_INSPECTOR_LOADED=1

# shellcheck source=inspectors/wordpress/common.sh
source "${MST_INSPECTOR_DIR}/wordpress/common.sh"

# Collect one WordPress site without letting failures stop the module.
mst_wordpress_run_collector() {
    local site_index="${1:?site index required}"
    local name="${2:?name required}"
    local url="${3:?url required}"
    local document_root="${4:-}"
    local wp_config_path="${5:-}"
    local wp_cli_path="${6:?wp cli path required}"
    local enabled="${7:?enabled required}"
    local record_var="MST_WORDPRESS_${site_index}_RECORD"
    local details_var="MST_WORDPRESS_${site_index}_DETAILS"
    local errors_var="MST_WORDPRESS_${site_index}_ERRORS"
    local rows_var="MST_WORDPRESS_${site_index}_ROWS"
    local record_json
    local -n status_ref="MST_WORDPRESS_RECORD_STATUSES"
    local -n severity_ref="MST_WORDPRESS_RECORD_SEVERITIES"
    local -n record_jsons_ref="MST_WORDPRESS_RECORD_JSONS"
    local -n titles_ref="MST_WORDPRESS_SECTION_TITLES"

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

    if ! mst_wordpress_collect_site "${site_index}" "${name}" "${url}" "${document_root}" "${wp_config_path}" "${wp_cli_path}" "${enabled}" "${record_var}" "${details_var}" "${errors_var}" "${rows_var}"; then
        mst_wordpress_build_internal_failure_record "${site_index}" "${name}" "${record_var}" "${details_var}" "${errors_var}" "Collector execution failed unexpectedly."
    fi

    record_json="$(mst_mrrf_record_json "${record_var}" "${details_var}" "${errors_var}")"
    record_jsons_ref+=("${record_json}")
    status_ref+=("${record_ref[status]}")
    severity_ref+=("${record_ref[severity]}")
    titles_ref+=("${name}")
}

# Collect the full WordPress report and expose the aggregate MRRF1 document.
mst_wordpress_collect_report() {
    local generated_at hostname report_status report_severity report_risk report_exit_code report_json
    local module_summary_json
    local site_index name url document_root wp_config_path wp_cli_path enabled

    declare -ga MST_WORDPRESS_RECORD_JSONS=()
    declare -ga MST_WORDPRESS_RECORD_STATUSES=()
    declare -ga MST_WORDPRESS_RECORD_SEVERITIES=()
    declare -ga MST_WORDPRESS_SECTION_TITLES=()
    declare -ga MST_WORDPRESS_SECTION_RECORDS=()
    declare -ga MST_WORDPRESS_SECTION_ROWS=()

    mst_wordpress_init_defaults
    site_index=0
    while IFS='|' read -r name url document_root wp_config_path wp_cli_path enabled; do
        [[ -n "${name}" ]] || continue
        site_index=$(( site_index + 1 ))
        mst_wordpress_run_collector "${site_index}" "${name}" "${url}" "${document_root}" "${wp_config_path}" "${wp_cli_path}" "${enabled}"
        MST_WORDPRESS_SECTION_RECORDS+=("MST_WORDPRESS_${site_index}_RECORD")
        MST_WORDPRESS_SECTION_ROWS+=("MST_WORDPRESS_${site_index}_ROWS")
    done < <(mst_wordpress_targets_catalog)

    generated_at="$(mst_mrrf_now_utc)"
    hostname="$(mst_wordpress_detect_hostname)"
    if [[ "${#MST_WORDPRESS_RECORD_STATUSES[@]}" -eq 0 ]]; then
        report_status="unknown"
        report_severity="unknown"
        report_exit_code="${MST_EXIT_PARTIAL}"
    else
        report_status="$(mst_wordpress_worst_status MST_WORDPRESS_RECORD_STATUSES)"
        report_severity="$(mst_wordpress_worst_severity MST_WORDPRESS_RECORD_SEVERITIES)"
        report_exit_code="$(mst_wordpress_report_exit_code MST_WORDPRESS_RECORD_STATUSES)"
    fi
    report_risk="$(mst_mrrf_risk_level_for_status "${report_status}")"
    module_summary_json="$(mst_wordpress_module_summary_json "wordpress" "${#MST_WORDPRESS_RECORD_JSONS[@]}" "${report_status}" "${report_severity}")"

    report_json="$(printf '{"schema_version":1,"document_type":"report","toolkit":"mst","toolkit_version":"%s","command":"wordpress","generated_at":"%s","host":{"hostname":"%s"},"records":[%s],"aggregate":{"record_count":%s,"overall_status":"%s","overall_severity":"%s","overall_score":null,"risk_level":"%s","module_summaries":[%s]},"exit_code":%s}' \
        "$(mst_mrrf_json_escape "${MST_VERSION}")" \
        "$(mst_mrrf_json_escape "${generated_at}")" \
        "$(mst_mrrf_json_escape "${hostname}")" \
        "$(IFS=,; printf '%s' "${MST_WORDPRESS_RECORD_JSONS[*]}")" \
        "${#MST_WORDPRESS_RECORD_JSONS[@]}" \
        "$(mst_mrrf_json_escape "${report_status}")" \
        "$(mst_mrrf_json_escape "${report_severity}")" \
        "$(mst_mrrf_json_escape "${report_risk}")" \
        "${module_summary_json}" \
        "${report_exit_code}")"

    export MST_WORDPRESS_REPORT_JSON="${report_json}"
    export MST_WORDPRESS_REPORT_STATUS="${report_status}"
    export MST_WORDPRESS_REPORT_SEVERITY="${report_severity}"
    export MST_WORDPRESS_REPORT_EXIT_CODE="${report_exit_code}"
}
