#!/usr/bin/env bash
# MST backup module coordinator.

if [[ -n "${MST_BACKUP_INSPECTOR_LOADED:-}" ]]; then
    return
fi
readonly MST_BACKUP_INSPECTOR_LOADED=1

# shellcheck source=inspectors/backup/common.sh
source "${MST_INSPECTOR_DIR}/backup/common.sh"

# Collect one backup target without letting failures stop the module.
mst_backup_run_collector() {
    local target_index="${1:?target index required}"
    local name="${2:?name required}"
    local target_type="${3:?type required}"
    local location="${4:?location required}"
    local expected_frequency="${5:?frequency required}"
    local maximum_age_hours="${6:?max age required}"
    local minimum_size_mb="${7:?min size required}"
    local enabled="${8:?enabled required}"
    local record_var="MST_BACKUP_${target_index}_RECORD"
    local details_var="MST_BACKUP_${target_index}_DETAILS"
    local errors_var="MST_BACKUP_${target_index}_ERRORS"
    local rows_var="MST_BACKUP_${target_index}_ROWS"
    local record_json
    local -n status_ref="MST_BACKUP_RECORD_STATUSES"
    local -n severity_ref="MST_BACKUP_RECORD_SEVERITIES"
    local -n record_jsons_ref="MST_BACKUP_RECORD_JSONS"
    local -n titles_ref="MST_BACKUP_SECTION_TITLES"

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

    if ! mst_backup_collect_target "${target_index}" "${name}" "${target_type}" "${location}" "${expected_frequency}" "${maximum_age_hours}" "${minimum_size_mb}" "${enabled}" "${record_var}" "${details_var}" "${errors_var}" "${rows_var}"; then
        mst_backup_build_internal_failure_record "${target_index}" "${name}" "${record_var}" "${details_var}" "${errors_var}" "Collector execution failed unexpectedly."
    fi

    record_json="$(mst_mrrf_record_json "${record_var}" "${details_var}" "${errors_var}")"
    record_jsons_ref+=("${record_json}")
    status_ref+=("${record_ref[status]}")
    severity_ref+=("${record_ref[severity]}")
    titles_ref+=("${name}")
}

# Collect the full backup report and expose the aggregate MRRF1 document.
mst_backup_collect_report() {
    local generated_at hostname report_status report_severity report_risk report_exit_code report_json
    local module_summary_json
    local target_index name target_type location expected_frequency maximum_age_hours minimum_size_mb enabled

    declare -ga MST_BACKUP_RECORD_JSONS=()
    declare -ga MST_BACKUP_RECORD_STATUSES=()
    declare -ga MST_BACKUP_RECORD_SEVERITIES=()
    declare -ga MST_BACKUP_SECTION_TITLES=()
    declare -ga MST_BACKUP_SECTION_RECORDS=()
    declare -ga MST_BACKUP_SECTION_ROWS=()

    mst_backup_init_defaults
    target_index=0
    while IFS='|' read -r name target_type location expected_frequency maximum_age_hours minimum_size_mb enabled; do
        [[ -n "${name}" ]] || continue
        target_index=$(( target_index + 1 ))
        mst_backup_run_collector "${target_index}" "${name}" "${target_type}" "${location}" "${expected_frequency}" "${maximum_age_hours}" "${minimum_size_mb}" "${enabled}"
        MST_BACKUP_SECTION_RECORDS+=("MST_BACKUP_${target_index}_RECORD")
        MST_BACKUP_SECTION_ROWS+=("MST_BACKUP_${target_index}_ROWS")
    done < <(mst_backup_targets_catalog)

    generated_at="$(mst_mrrf_now_utc)"
    hostname="$(mst_backup_detect_hostname)"
    if [[ "${#MST_BACKUP_RECORD_STATUSES[@]}" -eq 0 ]]; then
        report_status="unknown"
        report_severity="unknown"
        report_exit_code="${MST_EXIT_PARTIAL}"
    else
        report_status="$(mst_backup_worst_status MST_BACKUP_RECORD_STATUSES)"
        report_severity="$(mst_backup_worst_severity MST_BACKUP_RECORD_SEVERITIES)"
        report_exit_code="$(mst_backup_report_exit_code MST_BACKUP_RECORD_STATUSES)"
    fi
    report_risk="$(mst_mrrf_risk_level_for_status "${report_status}")"
    module_summary_json="$(mst_backup_module_summary_json "backup" "${#MST_BACKUP_RECORD_JSONS[@]}" "${report_status}" "${report_severity}")"

    report_json="$(printf '{"schema_version":1,"document_type":"report","toolkit":"mst","toolkit_version":"%s","command":"backup","generated_at":"%s","host":{"hostname":"%s"},"records":[%s],"aggregate":{"record_count":%s,"overall_status":"%s","overall_severity":"%s","overall_score":null,"risk_level":"%s","module_summaries":[%s]},"exit_code":%s}' \
        "$(mst_mrrf_json_escape "${MST_VERSION}")" \
        "$(mst_mrrf_json_escape "${generated_at}")" \
        "$(mst_mrrf_json_escape "${hostname}")" \
        "$(IFS=,; printf '%s' "${MST_BACKUP_RECORD_JSONS[*]}")" \
        "${#MST_BACKUP_RECORD_JSONS[@]}" \
        "$(mst_mrrf_json_escape "${report_status}")" \
        "$(mst_mrrf_json_escape "${report_severity}")" \
        "$(mst_mrrf_json_escape "${report_risk}")" \
        "${module_summary_json}" \
        "${report_exit_code}")"

    export MST_BACKUP_REPORT_JSON="${report_json}"
    export MST_BACKUP_REPORT_STATUS="${report_status}"
    export MST_BACKUP_REPORT_SEVERITY="${report_severity}"
    export MST_BACKUP_REPORT_EXIT_CODE="${report_exit_code}"
}
