#!/usr/bin/env bash
# Text renderer for the services module.

if [[ -n "${MST_SERVICES_RENDERER_LOADED:-}" ]]; then
    return
fi
readonly MST_SERVICES_RENDERER_LOADED=1

# Return a status badge for MRRF1 services statuses.
mst_services_status_badge() {
    case "${1:-unknown}" in
        ok) mst_status_badge ACTIVE ;;
        warn) mst_status_badge INACTIVE ;;
        critical) mst_status_badge FAILED ;;
        unavailable) printf '[UNAVAILABLE]' ;;
        unknown|skipped) printf '[%s]' "${1^^}" ;;
        *) printf '[%s]' "${1^^}" ;;
    esac
}

# Render one service record section from row data.
mst_render_services_rows_section() {
    local title="${1:?title required}"
    local record_name="${2:?record name required}"
    local rows_name="${3:?rows name required}"
    local -n record_ref="${record_name}"
    local -n rows_ref="${rows_name}"
    local row label value

    mst_section "${title}"
    printf '%s %s\n' "$(mst_services_status_badge "${record_ref[status]}")" "${record_ref[summary]}"
    for row in "${rows_ref[@]}"; do
        IFS="${MST_MRRF_FIELD_SEPARATOR}" read -r label value <<< "${row}"
        mst_table_row "${label}" "${value}"
    done
}

# Render the full services report in terminal-friendly text.
mst_render_services_report_text() {
    local service_id service_label upper_id record_var rows_var

    mst_header "$(mst_version_string)"
    mst_section "Services"
    printf '%s Aggregate status: %s\n' "$(mst_services_status_badge "${MST_SERVICES_REPORT_STATUS}")" "${MST_SERVICES_REPORT_STATUS}"

    while IFS='|' read -r service_id service_label _candidates; do
        [[ -n "${service_id}" ]] || continue
        upper_id="${service_id^^}"
        record_var="MST_SERVICES_${upper_id}_RECORD"
        rows_var="MST_SERVICES_${upper_id}_ROWS"
        mst_render_services_rows_section "${service_label}" "${record_var}" "${rows_var}"
    done < <(mst_services_service_catalog)
}
