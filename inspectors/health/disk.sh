#!/usr/bin/env bash
# Disk health collector.

# Collect one statfs snapshot for a mount path.
mst_health_disk_statfs() {
    local mount_point="${1:?mount point required}"
    stat -f -c '%b|%f|%a|%S|%c|%d' -- "${mount_point}"
}

# Return success if the mount should be ignored for health reporting.
mst_health_disk_should_ignore() {
    local source_name="${1:?source required}"
    local mount_point="${2:?mount point required}"
    local fs_type="${3:?fs type required}"

    case "${fs_type}" in
        tmpfs|devtmpfs|overlay|squashfs) return 0 ;;
    esac
    [[ "${source_name}" == /dev/loop* ]] && return 0
    [[ "${mount_point}" == /var/lib/docker/overlay2/* ]] && return 0
    [[ "${source_name}" == /dev/* ]] || return 0
    return 1
}

# Collect local filesystem capacity and inode usage.
mst_health_collect_disk() {
    local record_name="${1:?record name required}"
    local details_name="${2:?details name required}"
    local errors_name="${3:?errors name required}"
    local rows_name="${4:?rows name required}"
    local -n record_ref="${record_name}"
    local started_ms mount_line source_name mount_point fs_type options rest
    local fs_rows=0 worst_percent=0 worst_status="ok" worst_severity="ok" threshold_state status severity
    local stat_output total_blocks free_blocks avail_blocks block_size total_inodes free_inodes
    local total_mib used_mib avail_mib use_percent inode_use_percent mount_key

    mst_health_init_data_sources
    started_ms="$(mst_mrrf_now_epoch_ms)"
    mst_health_record_init "${record_name}" "res_health.disk_snapshot" "disk_usage" "local_filesystems" "procfs,filesystem,derived" "Derived from procfs mount metadata and statfs snapshots."

    [[ -r "${MST_HEALTH_MOUNTS_FILE}" ]] || {
        mst_health_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "Mounted filesystem data is unavailable." "$(mst_health_source_error_category "${MST_HEALTH_MOUNTS_FILE}")" "MOUNTS_UNAVAILABLE" "Cannot read the procfs mount list."
        mst_health_record_finalize "${record_name}" "${started_ms}"
        return 0
    }

    while IFS= read -r mount_line || [[ -n "${mount_line}" ]]; do
        read -r source_name mount_point fs_type options rest <<< "${mount_line}" || continue
        source_name="$(mst_health_decode_mount_field "${source_name}")"
        mount_point="$(mst_health_decode_mount_field "${mount_point}")"
        fs_type="$(mst_health_decode_mount_field "${fs_type}")"

        if mst_health_disk_should_ignore "${source_name}" "${mount_point}" "${fs_type}"; then
            continue
        fi

        stat_output="$(mst_health_disk_statfs "${mount_point}" 2>/dev/null)" || continue
        IFS='|' read -r total_blocks free_blocks avail_blocks block_size total_inodes free_inodes <<< "${stat_output}" || continue
        [[ "${total_blocks}" =~ ^[0-9]+$ ]] || continue
        [[ "${free_blocks}" =~ ^[0-9]+$ ]] || continue
        [[ "${avail_blocks}" =~ ^[0-9]+$ ]] || continue
        [[ "${block_size}" =~ ^[0-9]+$ ]] || continue
        [[ "${total_inodes}" =~ ^[0-9]+$ ]] || continue
        [[ "${free_inodes}" =~ ^[0-9]+$ ]] || continue
        (( total_blocks > 0 )) || continue

        total_mib=$(( (total_blocks * block_size) / 1048576 ))
        used_mib=$(( ((total_blocks - free_blocks) * block_size) / 1048576 ))
        avail_mib=$(( (avail_blocks * block_size) / 1048576 ))
        use_percent=$(( (100 * (total_blocks - free_blocks)) / total_blocks ))

        if (( total_inodes > 0 )); then
            inode_use_percent=$(( (100 * (total_inodes - free_inodes)) / total_inodes ))
        else
            inode_use_percent=0
        fi

        threshold_state="$(mst_health_threshold_status "${use_percent}" "${MST_HEALTH_DISK_WARN_PERCENT}" "${MST_HEALTH_DISK_ERROR_PERCENT}")"
        IFS='|' read -r status severity <<< "${threshold_state}"
        if (( use_percent > worst_percent )); then
            worst_percent="${use_percent}"
            worst_status="${status}"
            worst_severity="${severity}"
        fi

        fs_rows=$(( fs_rows + 1 ))
        mount_key="fs_$(printf '%02d' "${fs_rows}")"
        mst_health_add_detail "${details_name}" "${mount_key}" "Filesystem ${fs_rows}" "string" "${mount_point} ${source_name} ${total_mib}MiB ${used_mib}MiB ${avail_mib}MiB ${use_percent}% inode ${inode_use_percent}%" "" "false"
        mst_health_add_row "${rows_name}" "${mount_point}" "${source_name}${MST_MRRF_FIELD_SEPARATOR}${fs_type}${MST_MRRF_FIELD_SEPARATOR}${total_mib}${MST_MRRF_FIELD_SEPARATOR}${used_mib}${MST_MRRF_FIELD_SEPARATOR}${avail_mib}${MST_MRRF_FIELD_SEPARATOR}${use_percent}${MST_MRRF_FIELD_SEPARATOR}${inode_use_percent}"
    done < "${MST_HEALTH_MOUNTS_FILE}"

    if (( fs_rows == 0 )); then
        mst_health_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "No eligible local filesystems were observed." "unknown" "NO_LOCAL_FILESYSTEMS" "No local filesystems remained after filtering."
        mst_health_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    record_ref[status]="${worst_status}"
    record_ref[severity]="${worst_severity}"
    record_ref[summary]="Observed ${fs_rows} local filesystems; highest usage is ${worst_percent}%."
    mst_health_add_detail "${details_name}" "filesystem_count" "Filesystem Count" "integer" "${fs_rows}" "" "false"
    mst_health_record_finalize "${record_name}" "${started_ms}"
}
