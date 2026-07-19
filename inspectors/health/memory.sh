#!/usr/bin/env bash
# Memory health collector.

# Read one numeric KiB field from /proc/meminfo.
mst_health_meminfo_kib() {
    local key_name="${1:?key name required}"
    local raw_value

    raw_value="$(mst_health_read_colon_value "${MST_HEALTH_PROC_DIR}/meminfo" "${key_name}")" || return 1
    raw_value="${raw_value%% *}"
    [[ "${raw_value}" =~ ^[0-9]+$ ]] || return 1
    printf '%s' "${raw_value}"
}

# Collect memory and swap utilization.
mst_health_collect_memory() {
    local record_name="${1:?record name required}"
    local details_name="${2:?details name required}"
    local errors_name="${3:?errors name required}"
    local rows_name="${4:?rows name required}"
    local -n record_ref="${record_name}"
    local started_ms mem_total mem_free mem_available buffers cached sreclaimable
    local swap_total swap_free swap_used mem_used mem_used_percent threshold_state status severity
    local mem_total_mib mem_used_mib mem_available_mib mem_free_mib buffers_mib cached_mib swap_total_mib swap_used_mib swap_free_mib

    mst_health_init_data_sources
    started_ms="$(mst_mrrf_now_epoch_ms)"
    mst_health_record_init "${record_name}" "res_health.memory_snapshot" "memory_usage" "localhost" "procfs,derived" "Derived from procfs memory information."

    mem_total="$(mst_health_meminfo_kib "MemTotal")" || {
        mst_health_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "Memory statistics are unavailable." "$(mst_health_source_error_category "${MST_HEALTH_PROC_DIR}/meminfo")" "MEMINFO_UNAVAILABLE" "Cannot read MemTotal from /proc/meminfo."
        mst_health_record_finalize "${record_name}" "${started_ms}"
        return 0
    }
    mem_free="$(mst_health_meminfo_kib "MemFree")" || mem_free=0
    mem_available="$(mst_health_meminfo_kib "MemAvailable")" || mem_available=$(( mem_total - mem_free ))
    buffers="$(mst_health_meminfo_kib "Buffers")" || buffers=0
    cached="$(mst_health_meminfo_kib "Cached")" || cached=0
    sreclaimable="$(mst_health_meminfo_kib "SReclaimable")" || sreclaimable=0
    cached=$(( cached + sreclaimable ))
    swap_total="$(mst_health_meminfo_kib "SwapTotal")" || swap_total=0
    swap_free="$(mst_health_meminfo_kib "SwapFree")" || swap_free=0

    if (( mem_available > mem_total )); then
        mst_health_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "Memory statistics were malformed." "unknown" "MEMINFO_MALFORMED" "MemAvailable exceeded MemTotal."
        mst_health_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    mem_used=$(( mem_total - mem_available ))
    swap_used=$(( swap_total - swap_free ))
    mem_used_percent=$(( (100 * mem_used) / mem_total ))
    threshold_state="$(mst_health_threshold_status "${mem_used_percent}" "${MST_HEALTH_MEMORY_WARN_PERCENT}" "${MST_HEALTH_MEMORY_ERROR_PERCENT}")"
    IFS='|' read -r status severity <<< "${threshold_state}"

    mem_total_mib="$(mst_health_kib_to_mib "${mem_total}")"
    mem_used_mib="$(mst_health_kib_to_mib "${mem_used}")"
    mem_available_mib="$(mst_health_kib_to_mib "${mem_available}")"
    mem_free_mib="$(mst_health_kib_to_mib "${mem_free}")"
    buffers_mib="$(mst_health_kib_to_mib "${buffers}")"
    cached_mib="$(mst_health_kib_to_mib "${cached}")"
    swap_total_mib="$(mst_health_kib_to_mib "${swap_total}")"
    swap_used_mib="$(mst_health_kib_to_mib "${swap_used}")"
    swap_free_mib="$(mst_health_kib_to_mib "${swap_free}")"

    record_ref[status]="${status}"
    record_ref[severity]="${severity}"
    record_ref[summary]="Memory utilization is ${mem_used_percent}% with ${mem_available_mib} MiB available."

    mst_health_add_detail "${details_name}" "mem_total_mib" "Memory Total" "integer" "${mem_total_mib}" "MiB" "false"
    mst_health_add_detail "${details_name}" "mem_used_mib" "Memory Used" "integer" "${mem_used_mib}" "MiB" "false"
    mst_health_add_detail "${details_name}" "mem_available_mib" "Memory Available" "integer" "${mem_available_mib}" "MiB" "false"
    mst_health_add_detail "${details_name}" "mem_free_mib" "Memory Free" "integer" "${mem_free_mib}" "MiB" "false"
    mst_health_add_detail "${details_name}" "buffers_mib" "Buffers" "integer" "${buffers_mib}" "MiB" "false"
    mst_health_add_detail "${details_name}" "cached_mib" "Cached" "integer" "${cached_mib}" "MiB" "false"
    mst_health_add_detail "${details_name}" "swap_total_mib" "Swap Total" "integer" "${swap_total_mib}" "MiB" "false"
    mst_health_add_detail "${details_name}" "swap_used_mib" "Swap Used" "integer" "${swap_used_mib}" "MiB" "false"
    mst_health_add_detail "${details_name}" "swap_free_mib" "Swap Free" "integer" "${swap_free_mib}" "MiB" "false"
    mst_health_add_row "${rows_name}" "Memory Total" "$(mst_health_format_mib "${mem_total_mib}")"
    mst_health_add_row "${rows_name}" "Memory Used" "$(mst_health_format_mib "${mem_used_mib}")"
    mst_health_add_row "${rows_name}" "Memory Available" "$(mst_health_format_mib "${mem_available_mib}")"
    mst_health_add_row "${rows_name}" "Memory Free" "$(mst_health_format_mib "${mem_free_mib}")"
    mst_health_add_row "${rows_name}" "Buffers" "$(mst_health_format_mib "${buffers_mib}")"
    mst_health_add_row "${rows_name}" "Cached" "$(mst_health_format_mib "${cached_mib}")"
    mst_health_add_row "${rows_name}" "Swap Total" "$(mst_health_format_mib "${swap_total_mib}")"
    mst_health_add_row "${rows_name}" "Swap Used" "$(mst_health_format_mib "${swap_used_mib}")"
    mst_health_add_row "${rows_name}" "Swap Free" "$(mst_health_format_mib "${swap_free_mib}")"
    mst_health_record_finalize "${record_name}" "${started_ms}"
}
