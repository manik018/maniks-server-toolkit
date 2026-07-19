#!/usr/bin/env bash
# Text renderer for the backup module.

if [[ -n "${MST_BACKUP_RENDERER_LOADED:-}" ]]; then
    return
fi
readonly MST_BACKUP_RENDERER_LOADED=1

# Return a status badge for MRRF1 backup statuses.
mst_backup_status_badge() {
    case "${1:-unknown}" in
        ok) mst_status_badge SUCCESS ;;
        warn) mst_status_badge WARNING ;;
        critical) mst_status_badge ERROR ;;
        unavailable) printf '[UNAVAILABLE]' ;;
        unknown|skipped) printf '[%s]' "${1^^}" ;;
        *) printf '[%s]' "${1^^}" ;;
    esac
}

# Render one backup record section from row data.
mst_render_backup_rows_section() {
    local title="${1:?title required}"
    local record_name="${2:?record required}"
    local rows_name="${3:?rows required}"
    local -n record_ref="${record_name}"
    local -n rows_ref="${rows_name}"
    local row label value

    mst_section "${title}"
    printf '%s %s\n' "$(mst_backup_status_badge "${record_ref[status]}")" "${record_ref[summary]}"
    for row in "${rows_ref[@]}"; do
        IFS="${MST_MRRF_FIELD_SEPARATOR}" read -r label value <<< "${row}"
        mst_table_row "${label}" "${value}"
    done
}

# Render the full backup report in terminal-friendly text.
mst_render_backup_report_text() {
    local index

    mst_header "$(mst_version_string)"
    mst_section "Backup"
    printf '%s Aggregate status: %s\n' "$(mst_backup_status_badge "${MST_BACKUP_REPORT_STATUS}")" "${MST_BACKUP_REPORT_STATUS}"

    if [[ "${#MST_BACKUP_SECTION_TITLES[@]}" -eq 0 ]]; then
        mst_table_row "Configured Targets" "none"
        return 0
    fi

    for (( index = 0; index < ${#MST_BACKUP_SECTION_TITLES[@]}; index++ )); do
        mst_render_backup_rows_section \
            "${MST_BACKUP_SECTION_TITLES[index]}" \
            "${MST_BACKUP_SECTION_RECORDS[index]}" \
            "${MST_BACKUP_SECTION_ROWS[index]}"
    done
}
