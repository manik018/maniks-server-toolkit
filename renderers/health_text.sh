#!/usr/bin/env bash
# Text renderer for the health module.

if [[ -n "${MST_HEALTH_RENDERER_LOADED:-}" ]]; then
    return
fi
readonly MST_HEALTH_RENDERER_LOADED=1

# Return a status badge for MRRF1 health statuses.
mst_health_status_badge() {
    case "${1:-unknown}" in
        ok) mst_status_badge OK ;;
        warn) mst_status_badge WARNING ;;
        critical) mst_status_badge ERROR ;;
        unavailable|unknown|skipped) printf '[%s]' "${1}" ;;
        *) printf '[%s]' "${1}" ;;
    esac
}

# Render one simple two-column section from row data.
mst_render_health_rows_section() {
    local title="${1:?title required}"
    local record_name="${2:?record name required}"
    local rows_name="${3:?rows name required}"
    local -n record_ref="${record_name}"
    local -n rows_ref="${rows_name}"
    local row label value

    mst_section "${title}"
    printf '%s %s\n' "$(mst_health_status_badge "${record_ref[status]}")" "${record_ref[summary]}"
    for row in "${rows_ref[@]}"; do
        IFS="${MST_MRRF_FIELD_SEPARATOR}" read -r label value <<< "${row}"
        mst_table_row "${label}" "${value}"
    done
}

# Render the disk section with one row per filesystem.
mst_render_health_disk_section() {
    local record_name="${1:?record name required}"
    local rows_name="${2:?rows name required}"
    local -n record_ref="${record_name}"
    local -n rows_ref="${rows_name}"
    local row mount_point source_name fs_type total_mib used_mib avail_mib use_percent inode_percent

    mst_section "Disk"
    printf '%s %s\n' "$(mst_health_status_badge "${record_ref[status]}")" "${record_ref[summary]}"
    printf '  %-18s %-18s %-8s %-10s %-10s %-10s %-8s %-8s\n' "Mount" "Filesystem" "Type" "Total" "Used" "Avail" "Use%" "Inode%"
    for row in "${rows_ref[@]}"; do
        IFS="${MST_MRRF_FIELD_SEPARATOR}" read -r mount_point source_name fs_type total_mib used_mib avail_mib use_percent inode_percent <<< "${row}"
        printf '  %-18s %-18s %-8s %-10s %-10s %-10s %-8s %-8s\n' \
            "${mount_point}" \
            "${source_name}" \
            "${fs_type}" \
            "$(mst_health_format_mib "${total_mib}")" \
            "$(mst_health_format_mib "${used_mib}")" \
            "$(mst_health_format_mib "${avail_mib}")" \
            "${use_percent}%" \
            "${inode_percent}%"
    done
}

# Render the full health report in terminal-friendly text.
mst_render_health_report_text() {
    mst_header "$(mst_version_string)"
    mst_section "Health"
    printf '%s Aggregate status: %s\n' "$(mst_health_status_badge "${MST_HEALTH_REPORT_STATUS}")" "${MST_HEALTH_REPORT_STATUS}"

    mst_render_health_rows_section "CPU" MST_HEALTH_CPU_RECORD MST_HEALTH_CPU_ROWS
    mst_render_health_rows_section "Memory" MST_HEALTH_MEMORY_RECORD MST_HEALTH_MEMORY_ROWS
    mst_render_health_disk_section MST_HEALTH_DISK_RECORD MST_HEALTH_DISK_ROWS
    mst_render_health_rows_section "Uptime" MST_HEALTH_UPTIME_RECORD MST_HEALTH_UPTIME_ROWS
    mst_render_health_rows_section "System" MST_HEALTH_SYSTEM_RECORD MST_HEALTH_SYSTEM_ROWS
}
