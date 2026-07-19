#!/usr/bin/env bash
# Text renderer for the security module.

if [[ -n "${MST_SECURITY_RENDERER_LOADED:-}" ]]; then
    return
fi
readonly MST_SECURITY_RENDERER_LOADED=1

# Return a status badge for MRRF1 security statuses.
mst_security_status_badge() {
    case "${1:-unknown}" in
        ok) mst_status_badge SUCCESS ;;
        warn) mst_status_badge WARNING ;;
        critical) mst_status_badge ERROR ;;
        unavailable) printf '[UNAVAILABLE]' ;;
        unknown|skipped) printf '[%s]' "${1^^}" ;;
        *) printf '[%s]' "${1^^}" ;;
    esac
}

# Render one security record section from row data.
mst_render_security_rows_section() {
    local title="${1:?title required}"
    local record_name="${2:?record name required}"
    local rows_name="${3:?rows name required}"
    local -n record_ref="${record_name}"
    local -n rows_ref="${rows_name}"
    local row label value

    mst_section "${title}"
    printf '%s %s\n' "$(mst_security_status_badge "${record_ref[status]}")" "${record_ref[summary]}"
    for row in "${rows_ref[@]}"; do
        IFS="${MST_MRRF_FIELD_SEPARATOR}" read -r label value <<< "${row}"
        mst_table_row "${label}" "${value}"
    done
}

# Render the full security report in terminal-friendly text.
mst_render_security_report_text() {
    local check_id check_label upper_id record_var rows_var

    mst_header "$(mst_version_string)"
    mst_section "Security"
    printf '%s Aggregate status: %s\n' "$(mst_security_status_badge "${MST_SECURITY_REPORT_STATUS}")" "${MST_SECURITY_REPORT_STATUS}"

    while IFS='|' read -r check_id check_label; do
        [[ -n "${check_id}" ]] || continue
        upper_id="${check_id^^}"
        record_var="MST_SECURITY_${upper_id}_RECORD"
        rows_var="MST_SECURITY_${upper_id}_ROWS"
        mst_render_security_rows_section "${check_label}" "${record_var}" "${rows_var}"
    done < <(mst_security_check_catalog)
}
