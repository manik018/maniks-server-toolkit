#!/usr/bin/env bash
# Telegram-friendly renderers for the unified report engine.

if [[ -n "${MST_REPORT_TELEGRAM_RENDERER_LOADED:-}" ]]; then
    return
fi
readonly MST_REPORT_TELEGRAM_RENDERER_LOADED=1

mst_report_telegram_status_dot() {
    case "${1:-unknown}" in
        ok) printf '🟢' ;;
        warn) printf '🟡' ;;
        critical) printf '🔴' ;;
        *) printf '⚪' ;;
    esac
}

mst_report_telegram_status_mark() {
    case "${1:-unknown}" in
        ok) printf '✓' ;;
        warn) printf '⚠' ;;
        critical) printf '❌' ;;
        *) printf '⚪' ;;
    esac
}

mst_report_telegram_timestamp() {
    date -u -d "${MST_REPORT_TIMESTAMP}" '+%Y-%m-%d %H:%M UTC' 2>/dev/null || printf '%s' "${MST_REPORT_TIMESTAMP}"
}

mst_report_telegram_module_summary() {
    local wanted_module="${1:?module required}"
    local row module_key label status ok_count warn_count critical_count unavailable_count unknown_count record_count
    for row in "${MST_REPORT_MODULE_SUMMARIES[@]}"; do
        IFS="${MST_MRRF_FIELD_SEPARATOR}" read -r module_key label status ok_count warn_count critical_count unavailable_count unknown_count record_count <<< "${row}"
        if [[ "${module_key}" == "${wanted_module}" ]]; then
            printf '%s|%s|%s|%s|%s|%s|%s|%s' "${label}" "${status}" "${ok_count}" "${warn_count}" "${critical_count}" "${unavailable_count}" "${unknown_count}" "${record_count}"
            return 0
        fi
    done
    return 1
}

mst_report_telegram_module_status() {
    local summary
    summary="$(mst_report_telegram_module_summary "${1:?module required}")" || {
        printf 'unavailable'
        return 0
    }
    IFS='|' read -r _label status _ok _warn _critical _unavailable _unknown _record_count <<< "${summary}"
    printf '%s' "${status}"
}

mst_report_telegram_record_field() {
    local row_index="${1:?index required}"
    local field_name="${2:?field required}"
    local row module_key target_name status_name summary_text check_name

    row="${MST_REPORT_RECORD_ROWS[${row_index}]}"
    IFS="${MST_MRRF_FIELD_SEPARATOR}" read -r module_key target_name status_name summary_text <<< "${row}"
    check_name="${MST_REPORT_RECORD_CHECKS[${row_index}]:-}"
    case "${field_name}" in
        module) printf '%s' "${module_key}" ;;
        target) printf '%s' "${target_name}" ;;
        status) printf '%s' "${status_name}" ;;
        summary) printf '%s' "${summary_text}" ;;
        check) printf '%s' "${check_name}" ;;
    esac
}

mst_report_telegram_health_record_json() {
    local check_name="${1:?check required}"
    local index
    for index in "${!MST_REPORT_RECORD_ROWS[@]}"; do
        [[ "$(mst_report_telegram_record_field "${index}" module)" == "health" ]] || continue
        [[ "$(mst_report_telegram_record_field "${index}" check)" == "${check_name}" ]] || continue
        printf '%s' "${MST_REPORT_RECORD_JSON[${index}]:-}"
        return 0
    done
    return 1
}

mst_report_telegram_health_record_summary() {
    local check_name="${1:?check required}"
    local index
    for index in "${!MST_REPORT_RECORD_ROWS[@]}"; do
        [[ "$(mst_report_telegram_record_field "${index}" module)" == "health" ]] || continue
        [[ "$(mst_report_telegram_record_field "${index}" check)" == "${check_name}" ]] || continue
        mst_report_telegram_record_field "${index}" summary
        return 0
    done
    return 1
}

mst_report_telegram_health_record_status() {
    local check_name="${1:?check required}"
    local index
    for index in "${!MST_REPORT_RECORD_ROWS[@]}"; do
        [[ "$(mst_report_telegram_record_field "${index}" module)" == "health" ]] || continue
        [[ "$(mst_report_telegram_record_field "${index}" check)" == "${check_name}" ]] || continue
        mst_report_telegram_record_field "${index}" status
        return 0
    done
    return 1
}

mst_report_telegram_health_detail_number() {
    local check_name="${1:?check required}"
    local detail_key="${2:?detail required}"
    local record_json
    record_json="$(mst_report_telegram_health_record_json "${check_name}")" || return 0
    mst_report_json_detail_number "${record_json}" "${detail_key}"
}

mst_report_telegram_health_detail_string() {
    local check_name="${1:?check required}"
    local detail_key="${2:?detail required}"
    local record_json
    record_json="$(mst_report_telegram_health_record_json "${check_name}")" || return 0
    mst_report_json_detail_string "${record_json}" "${detail_key}"
}

mst_report_telegram_format_uptime() {
    local seconds="${1:-}"
    local days hours minutes
    [[ "${seconds}" =~ ^[0-9]+$ ]] || return 1
    days=$(( seconds / 86400 ))
    hours=$(( (seconds % 86400) / 3600 ))
    minutes=$(( (seconds % 3600) / 60 ))
    if (( days > 0 )); then
        printf '%sd %sh %sm' "${days}" "${hours}" "${minutes}"
    elif (( hours > 0 )); then
        printf '%sh %sm' "${hours}" "${minutes}"
    else
        printf '%sm' "${minutes}"
    fi
}

mst_report_telegram_disk_max_percent() {
    local record_json fs_index detail_value usage max_usage=""
    record_json="$(mst_report_telegram_health_record_json disk_usage)" || return 0
    for fs_index in $(seq 1 99); do
        detail_value="$(mst_report_json_detail_string "${record_json}" "fs_$(printf '%02d' "${fs_index}")")"
        [[ -n "${detail_value}" ]] || continue
        usage="$(sed -n 's/.* \([0-9][0-9]*\)% inode .*/\1/p' <<< "${detail_value}" | head -n 1)"
        [[ "${usage}" =~ ^[0-9]+$ ]] || continue
        if [[ -z "${max_usage}" ]] || (( usage > max_usage )); then
            max_usage="${usage}"
        fi
    done
    printf '%s' "${max_usage}"
}

mst_report_telegram_disk_label() {
    case "$(mst_report_telegram_health_record_status disk_usage || true)" in
        critical) printf 'CRITICAL' ;;
        warn) printf 'WARN' ;;
        *) printf 'OK' ;;
    esac
}

mst_report_telegram_render_record_lines() {
    local module_key="${1:?module required}"
    local mode="${2:?mode required}"
    local index target status summary check mark
    for index in "${!MST_REPORT_RECORD_ROWS[@]}"; do
        [[ "$(mst_report_telegram_record_field "${index}" module)" == "${module_key}" ]] || continue
        target="$(mst_report_telegram_record_field "${index}" target)"
        status="$(mst_report_telegram_record_field "${index}" status)"
        summary="$(mst_report_telegram_record_field "${index}" summary)"
        check="$(mst_report_telegram_record_field "${index}" check)"
        mark="$(mst_report_telegram_status_mark "${status}")"
        case "${mode}" in
            services)
                if [[ "${status}" == "critical" && "${check}" == "service_status" ]]; then
                    printf '%s %s DOWN\n' "${mark}" "${target}"
                else
                    printf '%s %s\n' "${mark}" "${target}"
                fi
                ;;
            security)
                case "${status}" in
                    ok) printf '%s %s\n' "${mark}" "${target}" ;;
                    warn|critical) printf '%s %s\n' "${mark}" "${summary}" ;;
                    *) printf '%s %s\n' "${mark}" "${target}" ;;
                esac
                ;;
            target-summary)
                printf '%s %s - %s\n' "${mark}" "${target}" "${summary}"
                ;;
        esac
    done
}

mst_report_telegram_is_effectively_unconfigured() {
    local module_key="${1:?module required}"
    local summary status ok_count warn_count critical_count unavailable_count unknown_count record_count
    summary="$(mst_report_telegram_module_summary "${module_key}")" || return 0
    IFS='|' read -r _label status ok_count warn_count critical_count unavailable_count unknown_count record_count <<< "${summary}"
    (( record_count == unavailable_count + unknown_count )) || return 1
    (( ok_count == 0 && warn_count == 0 && critical_count == 0 ))
}

mst_render_report_telegram_full() {
    local cpu_percent memory_summary disk_label filesystem_count load_1m load_5m load_15m uptime_seconds uptime_text module_status

    printf '%s Manik'\''s Server Toolkit v%s\n\n' "$(mst_report_telegram_status_dot "${MST_REPORT_STATUS}")" "${MST_VERSION}"
    printf '📍 Server\n'
    printf 'Hostname: %s\n' "${MST_REPORT_HOSTNAME}"
    printf 'Time: %s\n' "$(mst_report_telegram_timestamp)"
    printf 'Overall: %s\n\n' "${MST_REPORT_OVERALL}"
    printf '━━━━━━━━━━━━━━━━━━\n\n'

    module_status="$(mst_report_telegram_module_status health)"
    printf '%s Health\n' "$(mst_report_telegram_status_dot "${module_status}")"
    cpu_percent="$(mst_report_telegram_health_detail_number cpu_usage cpu_percent)"
    if [[ -n "${cpu_percent}" ]]; then
        printf 'CPU: %s%%\n' "${cpu_percent}"
    else
        printf 'CPU: %s\n' "$(mst_report_telegram_health_record_summary cpu_usage)"
    fi
    memory_summary="$(mst_report_telegram_health_record_summary memory_usage || true)"
    if [[ "${memory_summary}" =~ Memory\ utilization\ is\ ([0-9]+)% ]]; then
        printf 'Memory: %s%%\n' "${BASH_REMATCH[1]}"
    elif [[ -n "${memory_summary}" ]]; then
        printf 'Memory: %s\n' "${memory_summary}"
    fi
    disk_label="$(mst_report_telegram_disk_label)"
    filesystem_count="$(mst_report_telegram_health_detail_number disk_usage filesystem_count)"
    if [[ -n "${filesystem_count}" ]]; then
        printf 'Disk: %s (%s filesystems)\n' "${disk_label}" "${filesystem_count}"
    fi
    load_1m="$(mst_report_telegram_health_detail_string cpu_usage load_1m)"
    load_5m="$(mst_report_telegram_health_detail_string cpu_usage load_5m)"
    load_15m="$(mst_report_telegram_health_detail_string cpu_usage load_15m)"
    if [[ -n "${load_1m}${load_5m}${load_15m}" ]]; then
        printf 'Load: %s / %s / %s\n' "${load_1m}" "${load_5m}" "${load_15m}"
    fi
    uptime_seconds="$(mst_report_telegram_health_detail_number uptime uptime_seconds)"
    if uptime_text="$(mst_report_telegram_format_uptime "${uptime_seconds}")"; then
        printf 'Uptime: %s\n' "${uptime_text}"
    else
        uptime_text="$(mst_report_telegram_health_record_summary uptime || true)"
        [[ -n "${uptime_text}" ]] && printf 'Uptime: %s\n' "${uptime_text}"
    fi
    printf '\n'

    printf '%s Services\n' "$(mst_report_telegram_status_dot "$(mst_report_telegram_module_status services)")"
    mst_report_telegram_render_record_lines services services
    printf '\n%s Security\n' "$(mst_report_telegram_status_dot "$(mst_report_telegram_module_status security)")"
    mst_report_telegram_render_record_lines security security

    printf '\n%s Websites\n' "$(mst_report_telegram_status_dot "$(mst_report_telegram_module_status website)")"
    if mst_report_telegram_is_effectively_unconfigured website; then
        printf 'No websites configured.\n'
    else
        mst_report_telegram_render_record_lines website target-summary
    fi
    printf '\n%s WordPress\n' "$(mst_report_telegram_status_dot "$(mst_report_telegram_module_status wordpress)")"
    if mst_report_telegram_is_effectively_unconfigured wordpress; then
        printf 'No WordPress sites configured.\n'
    else
        mst_report_telegram_render_record_lines wordpress target-summary
    fi
    printf '\n%s Backups\n' "$(mst_report_telegram_status_dot "$(mst_report_telegram_module_status backup)")"
    if mst_report_telegram_is_effectively_unconfigured backup; then
        printf 'No backup targets configured.\n'
    else
        mst_report_telegram_render_record_lines backup target-summary
    fi

    printf '\n━━━━━━━━━━━━━━━━━━\n\n'
    printf 'Summary\n\n'
    printf '🟢 Success : %s\n' "${MST_REPORT_TOTAL_OK}"
    printf '🟡 Warning : %s\n' "${MST_REPORT_TOTAL_WARN}"
    printf '🔴 Error : %s\n' "${MST_REPORT_TOTAL_CRITICAL}"
    printf '⚪ Unknown : %s\n\n' "$(( MST_REPORT_TOTAL_UNAVAILABLE + MST_REPORT_TOTAL_UNKNOWN ))"
    printf 'Generated by Manik'\''s Server Toolkit\n'
}

mst_render_report_telegram_critical() {
    local index module target status summary check cpu_percent memory_summary disk_percent
    printf '🔴 CRITICAL SERVER ALERT\n\n'
    printf 'Server: %s\n\n' "${MST_REPORT_HOSTNAME}"
    for index in "${!MST_REPORT_RECORD_ROWS[@]}"; do
        status="$(mst_report_telegram_record_field "${index}" status)"
        [[ "${status}" == "critical" ]] || continue
        module="$(mst_report_telegram_record_field "${index}" module)"
        target="$(mst_report_telegram_record_field "${index}" target)"
        summary="$(mst_report_telegram_record_field "${index}" summary)"
        check="$(mst_report_telegram_record_field "${index}" check)"
        if [[ "${module}" == "services" && "${check}" == "service_status" ]]; then
            printf '❌ %s DOWN\n' "${target}"
        else
            printf '❌ %s - %s\n' "${target}" "${summary}"
        fi
    done
    printf '\n'
    cpu_percent="$(mst_report_telegram_health_detail_number cpu_usage cpu_percent)"
    [[ -n "${cpu_percent}" ]] && printf 'CPU: %s%%\n' "${cpu_percent}"
    memory_summary="$(mst_report_telegram_health_record_summary memory_usage || true)"
    [[ "${memory_summary}" =~ Memory\ utilization\ is\ ([0-9]+)% ]] && printf 'Memory: %s%%\n' "${BASH_REMATCH[1]}"
    disk_percent="$(mst_report_telegram_disk_max_percent)"
    [[ -n "${disk_percent}" ]] && printf 'Disk: %s%%\n' "${disk_percent}"
    printf '\nImmediate attention required.\n'
}

mst_render_report_telegram_digest() {
    local summary ok_count warn_count critical_count unavailable_count unknown_count record_count index status target summary_text seen_non_ok=0
    printf '%s Daily Server Report\n\n' "$(mst_report_telegram_status_dot "${MST_REPORT_STATUS}")"
    printf 'Overall: %s\n\n' "${MST_REPORT_OVERALL}"

    local cpu_percent memory_summary disk_label
    cpu_percent="$(mst_report_telegram_health_detail_number cpu_usage cpu_percent)"
    [[ -n "${cpu_percent}" ]] && printf 'CPU: %s%%\n' "${cpu_percent}"
    memory_summary="$(mst_report_telegram_health_record_summary memory_usage || true)"
    [[ "${memory_summary}" =~ Memory\ utilization\ is\ ([0-9]+)% ]] && printf 'Memory: %s%%\n' "${BASH_REMATCH[1]}"
    disk_label="$(mst_report_telegram_disk_label)"
    printf 'Disk: %s\n\n' "${disk_label}"

    printf 'Services:\n'
    if ! summary="$(mst_report_telegram_module_summary services)"; then
        printf '⚪ Not available\n'
    else
        IFS='|' read -r _label _status ok_count warn_count critical_count unavailable_count unknown_count record_count <<< "${summary}"
        if (( record_count > 0 && ok_count == record_count )); then
            printf '✅ All running\n'
        else
            for index in "${!MST_REPORT_RECORD_ROWS[@]}"; do
                [[ "$(mst_report_telegram_record_field "${index}" module)" == "services" ]] || continue
                status="$(mst_report_telegram_record_field "${index}" status)"
                [[ "${status}" == "ok" ]] && continue
                target="$(mst_report_telegram_record_field "${index}" target)"
                printf '%s %s\n' "$(mst_report_telegram_status_mark "${status}")" "${target}"
            done
        fi
    fi

    printf '\nSecurity:\n'
    summary="$(mst_report_telegram_module_summary security || true)"
    IFS='|' read -r _label _status ok_count warn_count critical_count _unavailable _unknown record_count <<< "${summary}"
    if (( record_count > 0 && ok_count == record_count )); then
        printf '✅ No issues\n'
    else
        for index in "${!MST_REPORT_RECORD_ROWS[@]}"; do
            [[ "$(mst_report_telegram_record_field "${index}" module)" == "security" ]] || continue
            status="$(mst_report_telegram_record_field "${index}" status)"
            [[ "${status}" == "warn" || "${status}" == "critical" ]] || continue
            summary_text="$(mst_report_telegram_record_field "${index}" summary)"
            printf '⚠ %s\n' "${summary_text}"
            seen_non_ok=1
        done
        (( seen_non_ok == 1 )) || printf '⚪ Not available\n'
    fi

    printf '\nWebsites:\n'
    if mst_report_telegram_is_effectively_unconfigured website; then
        printf 'None configured\n'
    else
        summary="$(mst_report_telegram_module_summary website)"
        IFS='|' read -r _label _status _ok_count _warn_count _critical_count _unavailable_count _unknown_count record_count <<< "${summary}"
        printf '%s monitored\n' "${record_count}"
    fi

    printf '\nWordPress:\n'
    if mst_report_telegram_is_effectively_unconfigured wordpress; then
        printf 'None configured\n'
    else
        summary="$(mst_report_telegram_module_summary wordpress)"
        IFS='|' read -r _label _status ok_count _warn_count _critical_count _unavailable_count _unknown_count _record_count <<< "${summary}"
        printf '%s healthy\n' "${ok_count}"
    fi

    printf '\nBackups:\n'
    if mst_report_telegram_is_effectively_unconfigured backup; then
        printf 'None configured\n'
    else
        mst_report_telegram_render_record_lines backup target-summary
    fi

    printf '\n'
    if (( MST_REPORT_TOTAL_CRITICAL == 0 )); then
        printf 'No critical issues detected.\n'
    else
        printf '⚠ %s critical issue(s) detected.\n' "${MST_REPORT_TOTAL_CRITICAL}"
    fi
}
