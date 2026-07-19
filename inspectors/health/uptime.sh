#!/usr/bin/env bash
# Uptime health collector.

# Collect uptime and boot-time information.
mst_health_collect_uptime() {
    local record_name="${1:?record name required}"
    local details_name="${2:?details name required}"
    local errors_name="${3:?errors name required}"
    local rows_name="${4:?rows name required}"
    local -n record_ref="${record_name}"
    local started_ms uptime_line uptime_seconds uptime_days stat_file line boot_time_epoch boot_time_iso

    mst_health_init_data_sources
    started_ms="$(mst_mrrf_now_epoch_ms)"
    mst_health_record_init "${record_name}" "res_health.uptime_snapshot" "uptime" "localhost" "procfs,derived" "Derived from procfs uptime and boot-time metadata."

    uptime_line="$(mst_health_read_file "${MST_HEALTH_PROC_DIR}/uptime" 2>/dev/null || true)"
    uptime_seconds="${uptime_line%% *}"
    [[ "${uptime_seconds}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || {
        mst_health_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "Uptime information is unavailable." "$(mst_health_source_error_category "${MST_HEALTH_PROC_DIR}/uptime")" "UPTIME_UNAVAILABLE" "Cannot parse /proc/uptime."
        mst_health_record_finalize "${record_name}" "${started_ms}"
        return 0
    }
    uptime_seconds="${uptime_seconds%.*}"
    uptime_days=$(( uptime_seconds / 86400 ))

    stat_file="${MST_HEALTH_PROC_DIR}/stat"
    if [[ -r "${stat_file}" ]]; then
        while IFS= read -r line || [[ -n "${line}" ]]; do
            if [[ "${line}" == btime\ * ]]; then
                boot_time_epoch="${line#btime }"
                break
            fi
        done < "${stat_file}"
    fi
    [[ "${boot_time_epoch:-}" =~ ^[0-9]+$ ]] || {
        mst_health_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "Boot time information is unavailable." "unknown" "BTIME_UNAVAILABLE" "The procfs boot time field was unavailable."
        mst_health_record_finalize "${record_name}" "${started_ms}"
        return 0
    }

    boot_time_iso="$(date -u -d "@${boot_time_epoch}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || printf '%s' "${boot_time_epoch}")"
    record_ref[status]="ok"
    record_ref[severity]="ok"
    record_ref[summary]="System uptime is $(mst_health_format_duration_seconds "${uptime_seconds}") since ${boot_time_iso}."
    mst_health_add_detail "${details_name}" "uptime_seconds" "Uptime" "integer" "${uptime_seconds}" "seconds" "false"
    mst_health_add_detail "${details_name}" "uptime_days" "Uptime Days" "integer" "${uptime_days}" "days" "false"
    mst_health_add_detail "${details_name}" "boot_time" "Boot Time" "string" "${boot_time_iso}" "" "false"
    mst_health_add_row "${rows_name}" "Uptime" "$(mst_health_format_duration_seconds "${uptime_seconds}")"
    mst_health_add_row "${rows_name}" "Boot Time" "${boot_time_iso}"
    mst_health_record_finalize "${record_name}" "${started_ms}"
}
