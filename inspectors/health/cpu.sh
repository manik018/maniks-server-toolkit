#!/usr/bin/env bash
# CPU health collector.

# Read aggregate CPU counters from /proc/stat.
mst_health_cpu_read_stat_line() {
    local stat_file="${MST_HEALTH_PROC_DIR}/stat"
    local line

    [[ -r "${stat_file}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" == cpu\ * ]] || continue
        printf '%s' "${line}"
        return 0
    done < "${stat_file}"
    return 1
}

# Convert one procfs cpu stat line into totals.
mst_health_cpu_parse_totals() {
    local stat_line="${1:?stat line required}"
    local cpu_label user nice system idle iowait irq softirq steal guest guest_nice
    local total idle_total

    read -r cpu_label user nice system idle iowait irq softirq steal guest guest_nice <<< "${stat_line}" || return 1
    total=$(( user + nice + system + idle + iowait + irq + softirq + steal + guest + guest_nice ))
    idle_total=$(( idle + iowait ))
    printf '%s|%s' "${total}" "${idle_total}"
}

# Collect CPU utilization and load averages.
mst_health_collect_cpu() {
    local record_name="${1:?record name required}"
    local details_name="${2:?details name required}"
    local errors_name="${3:?errors name required}"
    local rows_name="${4:?rows name required}"
    local -n record_ref="${record_name}"
    local started_ms stat_line_one stat_line_two totals_one totals_two
    local total_one idle_one total_two idle_two delta_total delta_idle cpu_percent
    local load_line load_one load_five load_fifteen threshold_state status severity

    mst_health_init_data_sources
    started_ms="$(mst_mrrf_now_epoch_ms)"
    mst_health_record_init "${record_name}" "res_health.cpu_snapshot" "cpu_usage" "localhost" "procfs,derived" "Derived from procfs cpu counters and load averages."

    stat_line_one="$(mst_health_cpu_read_stat_line)" || {
        if [[ "$(mst_health_source_error_category "${MST_HEALTH_PROC_DIR}/stat")" == "permission" ]]; then
            mst_health_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "CPU statistics require additional read access." "permission" "PROC_STAT_PERMISSION" "Read access to /proc/stat was denied."
        else
            mst_health_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "CPU statistics are unavailable." "dependency" "PROC_STAT_UNAVAILABLE" "Cannot read /proc/stat."
        fi
        mst_health_record_finalize "${record_name}" "${started_ms}"
        return 0
    }

    sleep "${MST_HEALTH_CPU_SAMPLE_SLEEP}"
    stat_line_two="$(mst_health_cpu_read_stat_line)" || {
        mst_health_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "CPU utilization could not be sampled twice." "unknown" "CPU_SAMPLE_INCOMPLETE" "Second /proc/stat sample was unavailable."
        mst_health_record_finalize "${record_name}" "${started_ms}"
        return 0
    }

    totals_one="$(mst_health_cpu_parse_totals "${stat_line_one}")" || {
        mst_health_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "CPU statistics were malformed." "unknown" "CPU_STAT_MALFORMED" "The first /proc/stat sample could not be parsed."
        mst_health_record_finalize "${record_name}" "${started_ms}"
        return 0
    }
    totals_two="$(mst_health_cpu_parse_totals "${stat_line_two}")" || {
        mst_health_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "CPU statistics were malformed." "unknown" "CPU_STAT_MALFORMED" "The second /proc/stat sample could not be parsed."
        mst_health_record_finalize "${record_name}" "${started_ms}"
        return 0
    }

    IFS='|' read -r total_one idle_one <<< "${totals_one}"
    IFS='|' read -r total_two idle_two <<< "${totals_two}"
    delta_total=$(( total_two - total_one ))
    delta_idle=$(( idle_two - idle_one ))
    if (( delta_total <= 0 )); then
        mst_health_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "CPU utilization could not be derived." "unknown" "CPU_DELTA_INVALID" "CPU sample delta was not positive."
        mst_health_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    cpu_percent=$(( (100 * (delta_total - delta_idle)) / delta_total ))

    load_line="$(mst_health_read_file "${MST_HEALTH_PROC_DIR}/loadavg" 2>/dev/null || true)"
    read -r load_one load_five load_fifteen _ <<< "${load_line}" || {
        if [[ ! -r "${MST_HEALTH_PROC_DIR}/loadavg" ]]; then
            mst_health_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "Load averages were unavailable." "$(mst_health_source_error_category "${MST_HEALTH_PROC_DIR}/loadavg")" "LOADAVG_UNAVAILABLE" "The /proc/loadavg file was unavailable."
        else
            mst_health_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "Load averages were unavailable." "unknown" "LOADAVG_MALFORMED" "The /proc/loadavg payload could not be parsed."
        fi
        mst_health_record_finalize "${record_name}" "${started_ms}"
        return 0
    }

    threshold_state="$(mst_health_threshold_status "${cpu_percent}" "${MST_HEALTH_CPU_WARN_PERCENT}" "${MST_HEALTH_CPU_ERROR_PERCENT}")"
    IFS='|' read -r status severity <<< "${threshold_state}"
    record_ref[status]="${status}"
    record_ref[severity]="${severity}"
    record_ref[summary]="CPU utilization is ${cpu_percent}% with load averages ${load_one}, ${load_five}, ${load_fifteen}."

    mst_health_add_detail "${details_name}" "cpu_percent" "CPU Utilization" "integer" "${cpu_percent}" "%" "false"
    mst_health_add_detail "${details_name}" "load_1m" "Load Average 1m" "string" "${load_one}" "" "false"
    mst_health_add_detail "${details_name}" "load_5m" "Load Average 5m" "string" "${load_five}" "" "false"
    mst_health_add_detail "${details_name}" "load_15m" "Load Average 15m" "string" "${load_fifteen}" "" "false"
    mst_health_add_row "${rows_name}" "CPU Utilization" "${cpu_percent}%"
    mst_health_add_row "${rows_name}" "Load Average 1m" "${load_one}"
    mst_health_add_row "${rows_name}" "Load Average 5m" "${load_five}"
    mst_health_add_row "${rows_name}" "Load Average 15m" "${load_fifteen}"
    mst_health_record_finalize "${record_name}" "${started_ms}"
}
