#!/usr/bin/env bash
# Shared helpers for the services module.

# Apply default configuration for service collectors.
mst_services_init_defaults() {
    export MST_SERVICES_PROC_DIR="${MST_SERVICES_PROC_DIR:-/proc}"
    export MST_SERVICES_NGINX_CANDIDATES="${MST_SERVICES_NGINX_CANDIDATES:-nginx.service}"
    export MST_SERVICES_PHP_FPM_CANDIDATES="${MST_SERVICES_PHP_FPM_CANDIDATES:-php8.3-fpm.service,php8.2-fpm.service,php8.1-fpm.service,php8.0-fpm.service,php7.4-fpm.service,php-fpm.service}"
    export MST_SERVICES_DATABASE_CANDIDATES="${MST_SERVICES_DATABASE_CANDIDATES:-mariadb.service,mysql.service}"
    export MST_SERVICES_REDIS_CANDIDATES="${MST_SERVICES_REDIS_CANDIDATES:-redis-server.service}"
    export MST_SERVICES_CRON_CANDIDATES="${MST_SERVICES_CRON_CANDIDATES:-cron.service,crond.service}"
    export MST_SERVICES_FAIL2BAN_CANDIDATES="${MST_SERVICES_FAIL2BAN_CANDIDATES:-fail2ban.service}"
    export MST_SERVICES_SSH_CANDIDATES="${MST_SERVICES_SSH_CANDIDATES:-ssh.service,sshd.service}"
}

# Return the default monitored service catalog.
mst_services_service_catalog() {
    cat <<EOF
nginx|Nginx|${MST_SERVICES_NGINX_CANDIDATES}
php_fpm|PHP-FPM|${MST_SERVICES_PHP_FPM_CANDIDATES}
database|Database|${MST_SERVICES_DATABASE_CANDIDATES}
redis|Redis|${MST_SERVICES_REDIS_CANDIDATES}
cron|Cron|${MST_SERVICES_CRON_CANDIDATES}
fail2ban|Fail2Ban|${MST_SERVICES_FAIL2BAN_CANDIDATES}
ssh|SSH|${MST_SERVICES_SSH_CANDIDATES}
EOF
}

# Return the label for a service family id.
mst_services_service_label() {
    local service_id="${1:?service id required}"
    while IFS='|' read -r catalog_id service_label _candidates; do
        if [[ "${catalog_id}" == "${service_id}" ]]; then
            printf '%s' "${service_label}"
            return 0
        fi
    done < <(mst_services_service_catalog)
    printf '%s' "${service_id}"
}

# Return the candidate unit list for a service family id.
mst_services_service_candidates() {
    local service_id="${1:?service id required}"
    while IFS='|' read -r catalog_id _service_label candidates; do
        if [[ "${catalog_id}" == "${service_id}" ]]; then
            printf '%s' "${candidates}"
            return 0
        fi
    done < <(mst_services_service_catalog)
    return 1
}

# Run systemctl show for one unit and return machine-readable properties.
mst_services_systemctl_show() {
    local unit_name="${1:?unit name required}"
    mst_exec_capture_stdout "${MST_TIMEOUT_SECONDS}" systemctl show --no-pager --property=Id,LoadState,ActiveState,SubState,UnitFileState,MainPID,MemoryCurrent,NRestarts,ActiveEnterTimestampMonotonic,Result "${unit_name}"
}

# Run systemctl is-active as a fallback when ActiveState is missing.
mst_services_systemctl_is_active() {
    local unit_name="${1:?unit name required}"
    mst_exec_capture_stdout "${MST_TIMEOUT_SECONDS}" systemctl is-active "${unit_name}"
}

# Run systemctl is-enabled as a fallback when UnitFileState is missing.
mst_services_systemctl_is_enabled() {
    local unit_name="${1:?unit name required}"
    mst_exec_capture_stdout "${MST_TIMEOUT_SECONDS}" systemctl is-enabled "${unit_name}"
}

# Read one property from a systemctl show payload.
mst_services_show_property() {
    local show_payload="${1:-}"
    local property_name="${2:?property required}"
    local line key value

    while IFS= read -r line || [[ -n "${line}" ]]; do
        key="${line%%=*}"
        if [[ "${key}" == "${property_name}" ]]; then
            value="${line#*=}"
            printf '%s' "${value}"
            return 0
        fi
    done <<< "${show_payload}"
    return 1
}

# Resolve the first available unit candidate for a service family.
mst_services_resolve_unit() {
    local service_id="${1:?service id required}"
    local candidates candidate payload load_state
    local -a candidate_array=()

    candidates="$(mst_services_service_candidates "${service_id}")" || return 1
    IFS=',' read -r -a candidate_array <<< "${candidates}"
    for candidate in "${candidate_array[@]}"; do
        [[ -n "${candidate}" ]] || continue
        payload="$(mst_services_systemctl_show "${candidate}" 2>/dev/null || true)"
        if ! mst_services_show_payload_valid "${payload}"; then
            if mst_services_is_permission_error "${payload}"; then
                printf '%s' "${candidate}"
                return 0
            fi
            continue
        fi
        load_state="$(mst_services_show_property "${payload}" "LoadState" || true)"
        if [[ "${load_state}" != "not-found" ]] && [[ -n "${load_state}" ]]; then
            printf '%s' "${candidate}"
            return 0
        fi
    done
    return 1
}

# Return success when a systemctl failure looks like a permission problem.
mst_services_is_permission_error() {
    local error_text="${1:-}"
    [[ "${error_text}" == *"Access denied"* ]] || [[ "${error_text}" == *"authentication required"* ]] || [[ "${error_text}" == *"Failed to connect to bus"* ]]
}

# Return success when a systemctl show payload contains expected properties.
mst_services_show_payload_valid() {
    local show_payload="${1:-}"
    [[ "${show_payload}" == *"LoadState="* ]] || [[ "${show_payload}" == *"ActiveState="* ]] || [[ "${show_payload}" == *"Id="* ]]
}

# Return the current hostname for aggregate documents.
mst_services_detect_hostname() {
    local hostname_file="${MST_SERVICES_PROC_DIR}/sys/kernel/hostname"
    if [[ -r "${hostname_file}" ]]; then
        tr -d '\n' < "${hostname_file}"
    else
        hostname 2>/dev/null || printf 'localhost'
    fi
}

# Read system uptime seconds from procfs for service uptime derivation.
mst_services_proc_uptime_seconds() {
    local uptime_file="${MST_SERVICES_PROC_DIR}/uptime"
    local uptime_line uptime_seconds

    [[ -r "${uptime_file}" ]] || return 1
    uptime_line="$(cat -- "${uptime_file}")"
    uptime_seconds="${uptime_line%% *}"
    [[ "${uptime_seconds}" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
    printf '%s' "${uptime_seconds%.*}"
}

# Convert monotonic microseconds since boot into service uptime seconds.
mst_services_uptime_seconds_from_monotonic() {
    local monotonic_us="${1:?monotonic us required}"
    local proc_uptime_seconds proc_uptime_us

    [[ "${monotonic_us}" =~ ^[0-9]+$ ]] || return 1
    proc_uptime_seconds="$(mst_services_proc_uptime_seconds)" || return 1
    proc_uptime_us=$(( proc_uptime_seconds * 1000000 ))
    (( proc_uptime_us >= monotonic_us )) || return 1
    printf '%s' "$(( (proc_uptime_us - monotonic_us) / 1000000 ))"
}

# Convert bytes into MiB.
mst_services_bytes_to_mib() {
    local bytes_value="${1:?bytes required}"
    printf '%s' "$(( bytes_value / 1048576 ))"
}

# Format a duration in seconds for terminal output.
mst_services_format_duration_seconds() {
    local total_seconds="${1:?seconds required}"
    local days hours minutes seconds

    days=$(( total_seconds / 86400 ))
    hours=$(( (total_seconds % 86400) / 3600 ))
    minutes=$(( (total_seconds % 3600) / 60 ))
    seconds=$(( total_seconds % 60 ))

    if (( days > 0 )); then
        printf '%sd %02dh %02dm %02ds' "${days}" "${hours}" "${minutes}" "${seconds}"
    else
        printf '%02dh %02dm %02ds' "${hours}" "${minutes}" "${seconds}"
    fi
}

# Format a memory value in MiB for terminal output.
mst_services_format_mib() {
    local value="${1:?MiB required}"
    if (( value >= 1024 )); then
        printf '%s GiB' "$(( value / 1024 ))"
    else
        printf '%s MiB' "${value}"
    fi
}

# Initialize one services MRRF1 record.
mst_services_record_init() {
    local record_name="${1:?record name required}"
    local result_id="${2:?result id required}"
    local target_name="${3:?target required}"
    local provenance="${4:?provenance required}"
    local -n record_ref="${record_name}"

    record_ref[result_id]="${result_id}"
    record_ref[module]="services"
    record_ref[check]="service_status"
    record_ref[target]="${target_name}"
    record_ref[status]="unknown"
    record_ref[severity]="unknown"
    record_ref[score]="null"
    record_ref[summary]="Service observation unavailable."
    record_ref[source_list]="systemd,derived"
    record_ref[provenance]="${provenance}"
    record_ref[privilege_requirement]="none"
    record_ref[redactions_present]="false"
}

# Finalize a services record with duration and timestamp.
mst_services_record_finalize() {
    local record_name="${1:?record name required}"
    local started_ms="${2:?started ms required}"
    local finished_ms duration_ms
    local -n record_ref="${record_name}"

    finished_ms="$(mst_mrrf_now_epoch_ms)"
    duration_ms=$(( finished_ms - started_ms ))
    record_ref[duration_ms]="${duration_ms}"
    record_ref[observed_at]="$(mst_mrrf_now_utc)"
}

# Append one MRRF1 detail to a detail array.
mst_services_add_detail() {
    local details_name="${1:?details array name required}"
    local key_name="${2:?key required}"
    local label="${3:?label required}"
    local value_type="${4:?value type required}"
    local value="${5:-}"
    local unit="${6:-}"
    local redacted="${7:-false}"
    local -n details_ref="${details_name}"

    details_ref+=("$(mst_mrrf_pack_detail "${key_name}" "${label}" "${value_type}" "${value}" "${unit}" "${redacted}")")
}

# Append one renderer row to a section row array.
mst_services_add_row() {
    local rows_name="${1:?rows array name required}"
    local label="${2:?label required}"
    local value="${3:-}"
    local -n rows_ref="${rows_name}"

    rows_ref+=("$(mst_mrrf_sanitize_text "${label}" 64)${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${value}" 200)")
}

# Append one MRRF1 error to an error array.
mst_services_add_error() {
    local errors_name="${1:?errors array name required}"
    local category="${2:?category required}"
    local code="${3:?code required}"
    local message="${4:?message required}"
    local -n errors_ref="${errors_name}"

    errors_ref+=("$(mst_mrrf_pack_error "${category}" "${code}" "${message}")")
}

# Mark a service record with a failure state.
mst_services_mark_failure() {
    local record_name="${1:?record name required}"
    local errors_name="${2:?errors array name required}"
    local status="${3:?status required}"
    local severity="${4:?severity required}"
    local summary="${5:?summary required}"
    local error_category="${6:?category required}"
    local error_code="${7:?error code required}"
    local error_message="${8:?error message required}"
    local -n record_ref="${record_name}"

    record_ref[status]="${status}"
    record_ref[severity]="${severity}"
    record_ref[summary]="${summary}"
    mst_services_add_error "${errors_name}" "${error_category}" "${error_code}" "${error_message}"
}

# Build a generic internal failure record for collector isolation.
mst_services_build_internal_failure_record() {
    local service_id="${1:?service id required}"
    local record_name="${2:?record name required}"
    local details_name="${3:?details array name required}"
    local errors_name="${4:?errors array name required}"
    local message="${5:?message required}"
    local started_ms
    local -n details_ref="${details_name}"
    local -n errors_ref="${errors_name}"

    started_ms="$(mst_mrrf_now_epoch_ms)"
    details_ref=()
    errors_ref=()
    mst_services_record_init "${record_name}" "res_services.${service_id}" "${service_id}" "Collector fallback path."
    mst_services_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "${message}" "internal" "COLLECTOR_FAILURE" "${message}"
    mst_services_record_finalize "${record_name}" "${started_ms}"
}

# Return the worst MRRF1 status from a status array.
mst_services_worst_status() {
    local array_name="${1:?array name required}"
    local -n values_ref="${array_name}"
    local value worst_value="ok" current_rank worst_rank=0

    for value in "${values_ref[@]}"; do
        current_rank="$(mst_mrrf_status_rank "${value}")"
        worst_rank="$(mst_mrrf_status_rank "${worst_value}")"
        if (( current_rank > worst_rank )); then
            worst_value="${value}"
        fi
    done
    printf '%s' "${worst_value}"
}

# Return the worst MRRF1 severity from a severity array.
mst_services_worst_severity() {
    local array_name="${1:?array name required}"
    local -n values_ref="${array_name}"
    local value rank worst_value="ok" worst_rank=0

    for value in "${values_ref[@]}"; do
        case "${value}" in
            critical) rank=3 ;;
            unknown) rank=2 ;;
            warning) rank=1 ;;
            ok) rank=0 ;;
            *) rank=2 ;;
        esac
        if (( rank > worst_rank )); then
            worst_rank="${rank}"
            worst_value="${value}"
        fi
    done
    printf '%s' "${worst_value}"
}

# Return the services command exit code from record statuses.
mst_services_report_exit_code() {
    local array_name="${1:?array name required}"
    local -n values_ref="${array_name}"
    local value

    for value in "${values_ref[@]}"; do
        case "${value}" in
            warn|critical|unknown|unavailable)
                printf '%s' "${MST_EXIT_PARTIAL}"
                return 0
                ;;
        esac
    done
    printf '%s' "${MST_EXIT_OK}"
}

# Build one module summary JSON object for services aggregate output.
mst_services_module_summary_json() {
    local module_name="${1:?module required}"
    local record_count="${2:?record count required}"
    local status="${3:?status required}"
    local severity="${4:?severity required}"

    printf '{"module":"%s","record_count":%s,"status":"%s","severity":"%s","score":null}' \
        "$(mst_mrrf_json_escape "${module_name}")" \
        "${record_count}" \
        "$(mst_mrrf_json_escape "${status}")" \
        "$(mst_mrrf_json_escape "${severity}")"
}

# Normalize one service state to MRRF1 status and severity.
mst_services_status_from_states() {
    local active_state="${1:-unknown}"
    local result_state="${2:-}"

    if [[ "${active_state}" == "failed" ]] || [[ "${result_state}" == "failed" ]]; then
        printf 'critical|critical'
    elif [[ "${active_state}" == "active" ]]; then
        printf 'ok|ok'
    elif [[ "${active_state}" == "inactive" ]]; then
        printf 'warn|warning'
    elif [[ "${active_state}" == "unknown" ]] || [[ -z "${active_state}" ]]; then
        printf 'unknown|unknown'
    else
        printf 'unknown|unknown'
    fi
}

# Collect one configured service family through systemd.
mst_services_collect_service() {
    local service_id="${1:?service id required}"
    local record_name="${2:?record name required}"
    local details_name="${3:?details array name required}"
    local errors_name="${4:?errors array name required}"
    local rows_name="${5:?rows name required}"
    local -n record_ref="${record_name}"
    local started_ms service_label resolved_unit show_output
    local load_state active_state sub_state unit_file_state main_pid memory_current n_restarts active_enter_monotonic result_state
    local fallback_active fallback_enabled status severity uptime_seconds uptime_display memory_mib failed_flag memory_display

    mst_services_init_defaults
    started_ms="$(mst_mrrf_now_epoch_ms)"
    service_label="$(mst_services_service_label "${service_id}")"
    mst_services_record_init "${record_name}" "res_services.${service_id}" "${service_label}" "Derived from systemd unit properties."

    resolved_unit="$(mst_services_resolve_unit "${service_id}")" || {
        mst_services_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "${service_label} service is not installed." "dependency" "SERVICE_NOT_FOUND" "No configured systemd unit was found for ${service_label}."
        mst_services_record_finalize "${record_name}" "${started_ms}"
        return 0
    }

    show_output="$(mst_services_systemctl_show "${resolved_unit}" 2>&1 || true)"
    if ! mst_services_show_payload_valid "${show_output}"; then
        if mst_services_is_permission_error "${show_output}"; then
            mst_services_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "${service_label} service requires additional read access." "permission" "SYSTEMCTL_PERMISSION" "systemctl show access was denied for ${resolved_unit}."
        else
            mst_services_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "${service_label} service state could not be determined." "unknown" "SYSTEMCTL_SHOW_FAILED" "systemctl show did not return properties for ${resolved_unit}."
        fi
        mst_services_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    load_state="$(mst_services_show_property "${show_output}" "LoadState" || true)"
    active_state="$(mst_services_show_property "${show_output}" "ActiveState" || true)"
    sub_state="$(mst_services_show_property "${show_output}" "SubState" || true)"
    unit_file_state="$(mst_services_show_property "${show_output}" "UnitFileState" || true)"
    main_pid="$(mst_services_show_property "${show_output}" "MainPID" || true)"
    memory_current="$(mst_services_show_property "${show_output}" "MemoryCurrent" || true)"
    n_restarts="$(mst_services_show_property "${show_output}" "NRestarts" || true)"
    active_enter_monotonic="$(mst_services_show_property "${show_output}" "ActiveEnterTimestampMonotonic" || true)"
    result_state="$(mst_services_show_property "${show_output}" "Result" || true)"

    if [[ "${load_state}" == "not-found" ]]; then
        mst_services_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "${service_label} service is not installed." "dependency" "SERVICE_NOT_FOUND" "systemd reported ${resolved_unit} as not found."
        mst_services_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    if [[ -z "${active_state}" ]]; then
        fallback_active="$(mst_services_systemctl_is_active "${resolved_unit}" 2>/dev/null || true)"
        active_state="${fallback_active:-unknown}"
    fi
    if [[ -z "${unit_file_state}" ]]; then
        fallback_enabled="$(mst_services_systemctl_is_enabled "${resolved_unit}" 2>/dev/null || true)"
        unit_file_state="${fallback_enabled:-unknown}"
    fi

    IFS='|' read -r status severity <<< "$(mst_services_status_from_states "${active_state}" "${result_state}")"
    record_ref[status]="${status}"
    record_ref[severity]="${severity}"
    record_ref[target]="${resolved_unit}"

    if [[ "${active_state}" == "active" ]] && [[ "${active_enter_monotonic}" =~ ^[0-9]+$ ]] && uptime_seconds="$(mst_services_uptime_seconds_from_monotonic "${active_enter_monotonic}" 2>/dev/null)"; then
        uptime_display="$(mst_services_format_duration_seconds "${uptime_seconds}")"
    else
        uptime_seconds=""
        uptime_display="n/a"
    fi

    if [[ "${memory_current}" =~ ^[0-9]+$ ]] && (( memory_current > 0 )); then
        memory_mib="$(mst_services_bytes_to_mib "${memory_current}")"
    else
        memory_mib=""
    fi

    if [[ ! "${main_pid}" =~ ^[0-9]+$ ]]; then
        main_pid="0"
    fi
    if [[ ! "${n_restarts}" =~ ^[0-9]+$ ]]; then
        n_restarts="0"
    fi
    if [[ "${active_state}" == "failed" ]] || [[ "${result_state}" == "failed" ]]; then
        failed_flag="true"
    else
        failed_flag="false"
    fi
    if [[ -n "${memory_mib}" ]]; then
        memory_display="$(mst_services_format_mib "${memory_mib}")"
    else
        memory_display="n/a"
    fi

    record_ref[summary]="${service_label} is ${active_state} with unit state ${unit_file_state:-unknown}."
    mst_services_add_detail "${details_name}" "service_name" "Service Name" "string" "${resolved_unit}" "" "false"
    mst_services_add_detail "${details_name}" "enabled_state" "Enabled State" "string" "${unit_file_state:-unknown}" "" "false"
    mst_services_add_detail "${details_name}" "active_state" "Active State" "string" "${active_state:-unknown}" "" "false"
    mst_services_add_detail "${details_name}" "failed_state" "Failed State" "boolean" "${failed_flag}" "" "false"
    mst_services_add_detail "${details_name}" "substate" "Substate" "string" "${sub_state:-unknown}" "" "false"
    mst_services_add_detail "${details_name}" "main_pid" "Main PID" "integer" "${main_pid}" "" "false"
    if [[ -n "${uptime_seconds}" ]]; then
        mst_services_add_detail "${details_name}" "uptime_seconds" "Service Uptime" "integer" "${uptime_seconds}" "seconds" "false"
    else
        mst_services_add_detail "${details_name}" "uptime_seconds" "Service Uptime" "null" "null" "" "false"
    fi
    if [[ -n "${memory_mib}" ]]; then
        mst_services_add_detail "${details_name}" "memory_mib" "Memory Usage" "integer" "${memory_mib}" "MiB" "false"
    else
        mst_services_add_detail "${details_name}" "memory_mib" "Memory Usage" "null" "null" "" "false"
    fi
    mst_services_add_detail "${details_name}" "restart_count" "Restart Count" "integer" "${n_restarts}" "" "false"

    mst_services_add_row "${rows_name}" "Unit" "${resolved_unit}"
    mst_services_add_row "${rows_name}" "Enabled" "${unit_file_state:-unknown}"
    mst_services_add_row "${rows_name}" "Active" "${active_state:-unknown}"
    mst_services_add_row "${rows_name}" "Failed" "${failed_flag}"
    mst_services_add_row "${rows_name}" "Substate" "${sub_state:-unknown}"
    mst_services_add_row "${rows_name}" "Main PID" "${main_pid}"
    mst_services_add_row "${rows_name}" "Memory Usage" "${memory_display}"
    mst_services_add_row "${rows_name}" "Restart Count" "${n_restarts}"
    mst_services_add_row "${rows_name}" "Uptime" "${uptime_display}"
    mst_services_record_finalize "${record_name}" "${started_ms}"
}
