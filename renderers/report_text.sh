#!/usr/bin/env bash
# Text renderer for the unified report engine.

if [[ -n "${MST_REPORT_RENDERER_LOADED:-}" ]]; then
    return
fi
readonly MST_REPORT_RENDERER_LOADED=1

# Return a status badge for MRRF1 report statuses.
mst_report_status_badge() {
    case "${1:-unknown}" in
        ok) mst_status_badge SUCCESS ;;
        warn) mst_status_badge WARNING ;;
        critical) mst_status_badge ERROR ;;
        unavailable) printf '[UNAVAILABLE]' ;;
        unknown|skipped) printf '[%s]' "${1^^}" ;;
        *) printf '[%s]' "${1^^}" ;;
    esac
}

# Return an uppercase label for one MRRF1 status.
mst_report_status_label() {
    case "${1:-unknown}" in
        ok) printf 'SUCCESS' ;;
        warn) printf 'WARNING' ;;
        critical) printf 'ERROR' ;;
        unavailable) printf 'UNAVAILABLE' ;;
        *) printf 'UNKNOWN' ;;
    esac
}

# Render individual records for one module section.
mst_render_report_records_for_module() {
    local module_key="${1:?module required}"
    local row row_module target_name status_name summary_text

    printf '  %-22s %-13s %s\n' "Record" "Status" "Summary"
    for row in "${MST_REPORT_RECORD_ROWS[@]}"; do
        IFS="${MST_MRRF_FIELD_SEPARATOR}" read -r row_module target_name status_name summary_text <<< "${row}"
        [[ "${row_module}" == "${module_key}" ]] || continue
        printf '  %-22s %-13s %s\n' \
            "${target_name}" \
            "$(mst_report_status_label "${status_name}")" \
            "${summary_text}"
    done
}

# Render the full unified report in terminal-friendly text.
mst_render_report_text() {
    local summary_row module_key label status_name ok_count warn_count critical_count unavailable_count unknown_count record_count

    mst_header "$(mst_version_string)"
    mst_section "Unified Report"
    mst_table_row "Hostname" "${MST_REPORT_HOSTNAME}"
    mst_table_row "Timestamp" "${MST_REPORT_TIMESTAMP}"
    mst_table_row "Overall Status" "$(mst_report_status_label "${MST_REPORT_STATUS}")"

    for summary_row in "${MST_REPORT_MODULE_SUMMARIES[@]}"; do
        IFS="${MST_MRRF_FIELD_SEPARATOR}" read -r module_key label status_name ok_count warn_count critical_count unavailable_count unknown_count record_count <<< "${summary_row}"
        mst_section "${label}"
        printf '%s Summary status: %s\n' "$(mst_report_status_badge "${status_name}")" "$(mst_report_status_label "${status_name}")"
        mst_table_row "Successful checks" "${ok_count}"
        mst_table_row "Warnings" "${warn_count}"
        mst_table_row "Errors" "${critical_count}"
        mst_table_row "Unavailable" "${unavailable_count}"
        mst_table_row "Unknown" "${unknown_count}"
        mst_table_row "Total records" "${record_count}"
        mst_render_report_records_for_module "${module_key}"
    done

    mst_section "Overall Summary"
    mst_table_row "Total modules" "${MST_REPORT_TOTAL_MODULES}"
    mst_table_row "Total records" "${MST_REPORT_TOTAL_RECORDS}"
    mst_table_row "SUCCESS count" "${MST_REPORT_TOTAL_OK}"
    mst_table_row "WARNING count" "${MST_REPORT_TOTAL_WARN}"
    mst_table_row "ERROR count" "${MST_REPORT_TOTAL_CRITICAL}"
    mst_table_row "UNAVAILABLE count" "${MST_REPORT_TOTAL_UNAVAILABLE}"
    mst_table_row "UNKNOWN count" "${MST_REPORT_TOTAL_UNKNOWN}"
}
