#!/usr/bin/env bash
# Shared helpers for the security module.

# Apply default configuration for security collectors.
mst_security_init_defaults() {
    export MST_SECURITY_PROC_DIR="${MST_SECURITY_PROC_DIR:-/proc}"
    export MST_SECURITY_SSH_SERVICE_CANDIDATES="${MST_SECURITY_SSH_SERVICE_CANDIDATES:-ssh.service,sshd.service}"
    export MST_SECURITY_SSH_CONFIG_FILE="${MST_SECURITY_SSH_CONFIG_FILE:-/etc/ssh/sshd_config}"
    export MST_SECURITY_UFW_CONF_FILE="${MST_SECURITY_UFW_CONF_FILE:-/etc/ufw/ufw.conf}"
    export MST_SECURITY_UFW_DEFAULTS_FILE="${MST_SECURITY_UFW_DEFAULTS_FILE:-/etc/default/ufw}"
    export MST_SECURITY_FAIL2BAN_SERVICE_CANDIDATES="${MST_SECURITY_FAIL2BAN_SERVICE_CANDIDATES:-fail2ban.service}"
    export MST_SECURITY_AUTO_UPGRADES_FILE="${MST_SECURITY_AUTO_UPGRADES_FILE:-/etc/apt/apt.conf.d/20auto-upgrades}"
    export MST_SECURITY_TIMESYNC_SERVICE_CANDIDATES="${MST_SECURITY_TIMESYNC_SERVICE_CANDIDATES:-systemd-timesyncd.service,chrony.service,chronyd.service,ntp.service}"
}

# Return the default security check catalog.
mst_security_check_catalog() {
    cat <<EOF
ssh|SSH
ufw|UFW
fail2ban|Fail2Ban
unattended_upgrades|Automatic Security Updates
time_sync|Time Synchronization
EOF
}

# Return the human-readable label for a security check id.
mst_security_check_label() {
    local check_id="${1:?check id required}"
    while IFS='|' read -r catalog_id check_label; do
        if [[ "${catalog_id}" == "${check_id}" ]]; then
            printf '%s' "${check_label}"
            return 0
        fi
    done < <(mst_security_check_catalog)
    printf '%s' "${check_id}"
}

# Read one file into stdout if it is available.
mst_security_read_file() {
    local file_path="${1:?file path required}"
    [[ -r "${file_path}" ]] || return 1
    cat -- "${file_path}"
}

# Trim leading and trailing whitespace from a string.
mst_security_trim() {
    local value="${1-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

# Return success if a systemctl error looks like a permission problem.
mst_security_is_permission_error() {
    local error_text="${1:-}"
    [[ "${error_text}" == *"Access denied"* ]] || [[ "${error_text}" == *"authentication required"* ]] || [[ "${error_text}" == *"Failed to connect to bus"* ]]
}

# Return success when a systemctl show payload contains expected properties.
mst_security_show_payload_valid() {
    local show_payload="${1:-}"
    [[ "${show_payload}" == *"LoadState="* ]] || [[ "${show_payload}" == *"ActiveState="* ]] || [[ "${show_payload}" == *"Id="* ]]
}

# Run systemctl show for one unit and return machine-readable properties.
mst_security_systemctl_show() {
    local unit_name="${1:?unit required}"
    mst_exec_capture_stdout "${MST_TIMEOUT_SECONDS}" systemctl show --no-pager --property=Id,LoadState,ActiveState,SubState,UnitFileState,Result "${unit_name}"
}

# Run systemctl is-active as a fallback.
mst_security_systemctl_is_active() {
    local unit_name="${1:?unit required}"
    mst_exec_capture_stdout "${MST_TIMEOUT_SECONDS}" systemctl is-active "${unit_name}"
}

# Run systemctl is-enabled as a fallback.
mst_security_systemctl_is_enabled() {
    local unit_name="${1:?unit required}"
    mst_exec_capture_stdout "${MST_TIMEOUT_SECONDS}" systemctl is-enabled "${unit_name}"
}

# Read one property from a systemctl show payload.
mst_security_show_property() {
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

# Resolve the first available unit candidate from a comma-separated list.
mst_security_resolve_unit() {
    local candidates="${1:?candidate list required}"
    local candidate payload load_state
    local -a candidate_array=()

    IFS=',' read -r -a candidate_array <<< "${candidates}"
    for candidate in "${candidate_array[@]}"; do
        [[ -n "${candidate}" ]] || continue
        payload="$(mst_security_systemctl_show "${candidate}" 2>/dev/null || true)"
        if ! mst_security_show_payload_valid "${payload}"; then
            if mst_security_is_permission_error "${payload}"; then
                printf '%s' "${candidate}"
                return 0
            fi
            continue
        fi
        load_state="$(mst_security_show_property "${payload}" "LoadState" || true)"
        if [[ -n "${load_state}" ]] && [[ "${load_state}" != "not-found" ]]; then
            printf '%s' "${candidate}"
            return 0
        fi
    done
    return 1
}

# Read and normalize one systemd unit state.
mst_security_unit_state() {
    local unit_name="${1:?unit required}"
    local output load_state active_state enabled_state result_state

    output="$(mst_security_systemctl_show "${unit_name}" 2>&1 || true)"
    if ! mst_security_show_payload_valid "${output}"; then
        printf 'error=%s\n' "$(mst_mrrf_sanitize_text "${output}" 200)"
        return 0
    fi

    load_state="$(mst_security_show_property "${output}" "LoadState" || true)"
    active_state="$(mst_security_show_property "${output}" "ActiveState" || true)"
    enabled_state="$(mst_security_show_property "${output}" "UnitFileState" || true)"
    result_state="$(mst_security_show_property "${output}" "Result" || true)"

    if [[ -z "${active_state}" ]]; then
        active_state="$(mst_security_systemctl_is_active "${unit_name}" 2>/dev/null || true)"
    fi
    if [[ -z "${enabled_state}" ]]; then
        enabled_state="$(mst_security_systemctl_is_enabled "${unit_name}" 2>/dev/null || true)"
    fi

    printf 'load=%s\nactive=%s\nenabled=%s\nresult=%s\n' "${load_state:-unknown}" "${active_state:-unknown}" "${enabled_state:-unknown}" "${result_state:-unknown}"
}

# Read a simple KEY=value assignment from a config file.
mst_security_read_assignment() {
    local file_path="${1:?file path required}"
    local key_name="${2:?key required}"
    local line trimmed key value

    [[ -r "${file_path}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        trimmed="${line%$'\r'}"
        trimmed="${trimmed%%#*}"
        trimmed="$(mst_security_trim "${trimmed}")"
        [[ -n "${trimmed}" ]] || continue
        key="${trimmed%%=*}"
        value="${trimmed#*=}"
        key="$(mst_security_trim "${key}")"
        value="$(mst_security_trim "${value}")"
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"
        if [[ "${key}" == "${key_name}" ]]; then
            printf '%s' "${value}"
            return 0
        fi
    done < "${file_path}"
    return 1
}

# Read one apt-style quoted value from a config file.
mst_security_read_apt_value() {
    local file_path="${1:?file path required}"
    local key_name="${2:?key required}"
    local line trimmed regex

    [[ -r "${file_path}" ]] || return 1
    regex="^[[:space:]]*${key_name}[[:space:]]+\"([^\"]+)\"[[:space:]]*;[[:space:]]*$"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        trimmed="${line%$'\r'}"
        if [[ "${trimmed}" =~ ${regex} ]]; then
            printf '%s' "${BASH_REMATCH[1]}"
            return 0
        fi
    done < "${file_path}"
    return 1
}

# Expand one SSH Include pattern relative to a base directory.
mst_security_ssh_expand_include() {
    local base_dir="${1:?base dir required}"
    local include_pattern="${2:?pattern required}"
    local array_name="${3:?array name required}"
    local candidate_pattern
    local -n array_ref="${array_name}"
    local old_nullglob
    local -a matches=()

    if [[ "${include_pattern}" == /* ]]; then
        candidate_pattern="${include_pattern}"
    else
        candidate_pattern="${base_dir}/${include_pattern}"
    fi

    old_nullglob="$(shopt -p nullglob || true)"
    shopt -s nullglob
    matches=( ${candidate_pattern} )
    eval "${old_nullglob:-shopt -u nullglob}"

    if [[ "${#matches[@]}" -eq 0 ]]; then
        return 0
    fi

    for candidate_pattern in "${matches[@]}"; do
        array_ref+=("${candidate_pattern}")
    done
}

# Parse one SSH configuration file for the monitored directives.
mst_security_ssh_parse_file() {
    local file_path="${1:?file required}"
    local settings_name="${2:?settings name required}"
    local queue_name="${3:?queue name required}"
    local line trimmed key value lower_key base_dir
    local -n settings_ref="${settings_name}"
    local -n queue_ref="${queue_name}"

    [[ -r "${file_path}" ]] || return 1
    base_dir="$(dirname "${file_path}")"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        trimmed="${line%$'\r'}"
        trimmed="${trimmed%%#*}"
        trimmed="$(mst_security_trim "${trimmed}")"
        [[ -n "${trimmed}" ]] || continue

        key="${trimmed%%[[:space:]]*}"
        value="${trimmed#"$key"}"
        value="$(mst_security_trim "${value}")"
        lower_key="${key,,}"

        case "${lower_key}" in
            include)
                mst_security_ssh_expand_include "${base_dir}" "${value}" "${queue_name}"
                ;;
            match)
                break
                ;;
            permitrootlogin|passwordauthentication|pubkeyauthentication)
                settings_ref["${lower_key}"]="${value,,}"
                ;;
        esac
    done < "${file_path}"
}

# Read the effective SSH security settings from config files.
mst_security_ssh_settings() {
    local config_file="${1:?config file required}"
    local settings_name="${2:?settings name required}"
    local queue_name="${3:?queue name required}"
    local file_path
    local -n settings_ref="${settings_name}"
    local -n queue_ref="${queue_name}"
    local -A seen_files=()

    if [[ ! -e "${config_file}" ]]; then
        return 2
    fi
    [[ -r "${config_file}" ]] || return 1

    queue_ref=("${config_file}")
    while [[ "${#queue_ref[@]}" -gt 0 ]]; do
        file_path="${queue_ref[0]}"
        queue_ref=("${queue_ref[@]:1}")
        [[ -n "${file_path}" ]] || continue
        [[ -n "${seen_files[${file_path}]:-}" ]] && continue
        seen_files["${file_path}"]=1
        [[ -f "${file_path}" ]] || continue
        mst_security_ssh_parse_file "${file_path}" "${settings_name}" "${queue_name}" || return 1
    done
    return 0
}

# Return current hostname for aggregate documents.
mst_security_detect_hostname() {
    local hostname_file="${MST_SECURITY_PROC_DIR}/sys/kernel/hostname"
    if [[ -r "${hostname_file}" ]]; then
        tr -d '\n' < "${hostname_file}"
    else
        hostname 2>/dev/null || printf 'localhost'
    fi
}

# Read timedatectl machine-readable synchronization state.
mst_security_timedatectl_show() {
    mst_exec_capture_stdout "${MST_TIMEOUT_SECONDS}" timedatectl show --property=NTPSynchronized --property=SystemClockSynchronized --property=CanNTP --property=NTP
}

# Read fail2ban-client status when available.
mst_security_fail2ban_status_output() {
    mst_exec_capture_stdout "${MST_TIMEOUT_SECONDS}" fail2ban-client status
}

# Parse the number of active fail2ban jails from status output.
mst_security_fail2ban_jail_count() {
    local status_output="${1:-}"
    local line

    while IFS= read -r line || [[ -n "${line}" ]]; do
        if [[ "${line}" =~ Number[[:space:]]+of[[:space:]]+jail:[[:space:]]*([0-9]+) ]]; then
            printf '%s' "${BASH_REMATCH[1]}"
            return 0
        fi
    done <<< "${status_output}"
    return 1
}

# Initialize one security MRRF1 record.
mst_security_record_init() {
    local record_name="${1:?record name required}"
    local result_id="${2:?result id required}"
    local check_name="${3:?check required}"
    local target_name="${4:?target required}"
    local source_list="${5:?sources required}"
    local provenance="${6:?provenance required}"
    local -n record_ref="${record_name}"

    record_ref[result_id]="${result_id}"
    record_ref[module]="security"
    record_ref[check]="${check_name}"
    record_ref[target]="${target_name}"
    record_ref[status]="unknown"
    record_ref[severity]="unknown"
    record_ref[score]="null"
    record_ref[summary]="Security observation unavailable."
    record_ref[source_list]="${source_list}"
    record_ref[provenance]="${provenance}"
    record_ref[privilege_requirement]="none"
    record_ref[redactions_present]="false"
}

# Finalize a security record with duration and timestamp.
mst_security_record_finalize() {
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
mst_security_add_detail() {
    local details_name="${1:?details array name required}"
    local key_name="${2:?key required}"
    local label="${3:?label required}"
    local value_type="${4:?type required}"
    local value="${5:-}"
    local unit="${6:-}"
    local redacted="${7:-false}"
    local -n details_ref="${details_name}"

    details_ref+=("$(mst_mrrf_pack_detail "${key_name}" "${label}" "${value_type}" "${value}" "${unit}" "${redacted}")")
}

# Append one renderer row.
mst_security_add_row() {
    local rows_name="${1:?rows array name required}"
    local label="${2:?label required}"
    local value="${3:-}"
    local -n rows_ref="${rows_name}"

    rows_ref+=("$(mst_mrrf_sanitize_text "${label}" 64)${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${value}" 200)")
}

# Append one MRRF1 error.
mst_security_add_error() {
    local errors_name="${1:?errors array name required}"
    local category="${2:?category required}"
    local code="${3:?code required}"
    local message="${4:?message required}"
    local -n errors_ref="${errors_name}"

    errors_ref+=("$(mst_mrrf_pack_error "${category}" "${code}" "${message}")")
}

# Mark a security record with a failure state.
mst_security_mark_failure() {
    local record_name="${1:?record name required}"
    local errors_name="${2:?errors array name required}"
    local status="${3:?status required}"
    local severity="${4:?severity required}"
    local summary="${5:?summary required}"
    local error_category="${6:?category required}"
    local error_code="${7:?code required}"
    local error_message="${8:?message required}"
    local -n record_ref="${record_name}"

    record_ref[status]="${status}"
    record_ref[severity]="${severity}"
    record_ref[summary]="${summary}"
    mst_security_add_error "${errors_name}" "${error_category}" "${error_code}" "${error_message}"
}

# Build a generic internal failure record for collector isolation.
mst_security_build_internal_failure_record() {
    local check_id="${1:?check id required}"
    local record_name="${2:?record name required}"
    local details_name="${3:?details name required}"
    local errors_name="${4:?errors name required}"
    local message="${5:?message required}"
    local started_ms
    local -n details_ref="${details_name}"
    local -n errors_ref="${errors_name}"

    started_ms="$(mst_mrrf_now_epoch_ms)"
    details_ref=()
    errors_ref=()
    mst_security_record_init "${record_name}" "res_security.${check_id}" "${check_id}" "${check_id}" "derived" "Collector fallback path."
    mst_security_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "${message}" "internal" "COLLECTOR_FAILURE" "${message}"
    mst_security_record_finalize "${record_name}" "${started_ms}"
}

# Return the worst MRRF1 status from a status array.
mst_security_worst_status() {
    local array_name="${1:?array required}"
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
mst_security_worst_severity() {
    local array_name="${1:?array required}"
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

# Return the security command exit code from record statuses.
mst_security_report_exit_code() {
    local array_name="${1:?array required}"
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

# Build one module summary JSON object.
mst_security_module_summary_json() {
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

# Add standard systemd service details to one record.
mst_security_add_service_details() {
    local details_name="${1:?details required}"
    local rows_name="${2:?rows required}"
    local service_name="${3:?service name required}"
    local active_state="${4:-unknown}"
    local enabled_state="${5:-unknown}"

    mst_security_add_detail "${details_name}" "service_name" "Service Name" "string" "${service_name}" "" "false"
    mst_security_add_detail "${details_name}" "service_active" "Service Active" "string" "${active_state}" "" "false"
    mst_security_add_detail "${details_name}" "service_enabled" "Service Enabled" "string" "${enabled_state}" "" "false"
    mst_security_add_row "${rows_name}" "Service" "${service_name}"
    mst_security_add_row "${rows_name}" "Active" "${active_state}"
    mst_security_add_row "${rows_name}" "Enabled" "${enabled_state}"
}

# Collect SSH service state and daemon security settings.
mst_security_collect_ssh() {
    local check_id="${1:?check id required}"
    local record_name="${2:?record required}"
    local details_name="${3:?details required}"
    local errors_name="${4:?errors required}"
    local rows_name="${5:?rows required}"
    local -n record_ref="${record_name}"
    local started_ms label resolved_unit state_output state_map
    local active_state enabled_state result_state
    local -A ssh_settings=(
        [permitrootlogin]="unknown"
        [passwordauthentication]="unknown"
        [pubkeyauthentication]="unknown"
    )
    local -a ssh_queue=()
    local ssh_parse_status status severity

    mst_security_init_defaults
    started_ms="$(mst_mrrf_now_epoch_ms)"
    label="$(mst_security_check_label "${check_id}")"
    mst_security_record_init "${record_name}" "res_security.${check_id}" "${check_id}" "${label}" "systemd,config" "Derived from systemd unit properties and sshd configuration."

    resolved_unit="$(mst_security_resolve_unit "${MST_SECURITY_SSH_SERVICE_CANDIDATES}")" || {
        mst_security_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "SSH service is not installed." "dependency" "SSH_SERVICE_NOT_FOUND" "No configured SSH systemd unit was found."
        mst_security_record_finalize "${record_name}" "${started_ms}"
        return 0
    }

    state_output="$(mst_security_unit_state "${resolved_unit}")"
    if [[ "${state_output}" == error=* ]]; then
        mst_security_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "SSH service state could not be determined." "unknown" "SYSTEMCTL_SHOW_FAILED" "${state_output#error=}"
        mst_security_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    declare -A state_map=()
    while IFS='=' read -r key value; do
        state_map["${key}"]="${value}"
    done <<< "${state_output}"
    active_state="${state_map[active]:-unknown}"
    enabled_state="${state_map[enabled]:-unknown}"
    result_state="${state_map[result]:-unknown}"

    ssh_parse_status=0
    mst_security_ssh_settings "${MST_SECURITY_SSH_CONFIG_FILE}" ssh_settings ssh_queue || ssh_parse_status=$?

    if [[ "${result_state}" == "failed" ]] || [[ "${active_state}" == "failed" ]]; then
        status="critical"
        severity="critical"
    elif [[ "${active_state}" != "active" ]] || [[ "${enabled_state}" == "disabled" ]]; then
        status="warn"
        severity="warning"
    else
        status="ok"
        severity="ok"
    fi

    if [[ "${ssh_parse_status}" -eq 2 ]]; then
        status="unknown"
        severity="unknown"
        mst_security_add_error "${errors_name}" "dependency" "SSH_CONFIG_MISSING" "SSH configuration file was not found."
    elif [[ "${ssh_parse_status}" -ne 0 ]]; then
        status="unavailable"
        severity="unknown"
        mst_security_add_error "${errors_name}" "permission" "SSH_CONFIG_UNREADABLE" "SSH configuration file could not be read."
    else
        case "${ssh_settings[permitrootlogin]}" in
            yes) status="warn"; severity="warning" ;;
        esac
        case "${ssh_settings[passwordauthentication]}" in
            yes) status="warn"; severity="warning" ;;
        esac
        case "${ssh_settings[pubkeyauthentication]}" in
            no) status="warn"; severity="warning" ;;
        esac
    fi

    record_ref[status]="${status}"
    record_ref[severity]="${severity}"
    record_ref[target]="${resolved_unit}"
    record_ref[summary]="SSH service is ${active_state} and ${enabled_state}. PermitRootLogin=${ssh_settings[permitrootlogin]}, PasswordAuthentication=${ssh_settings[passwordauthentication]}, PubkeyAuthentication=${ssh_settings[pubkeyauthentication]}."

    mst_security_add_service_details "${details_name}" "${rows_name}" "${resolved_unit}" "${active_state}" "${enabled_state}"
    mst_security_add_detail "${details_name}" "permit_root_login" "PermitRootLogin" "string" "${ssh_settings[permitrootlogin]}" "" "false"
    mst_security_add_detail "${details_name}" "password_authentication" "PasswordAuthentication" "string" "${ssh_settings[passwordauthentication]}" "" "false"
    mst_security_add_detail "${details_name}" "pubkey_authentication" "PubkeyAuthentication" "string" "${ssh_settings[pubkeyauthentication]}" "" "false"
    mst_security_add_row "${rows_name}" "PermitRootLogin" "${ssh_settings[permitrootlogin]}"
    mst_security_add_row "${rows_name}" "PasswordAuthentication" "${ssh_settings[passwordauthentication]}"
    mst_security_add_row "${rows_name}" "PubkeyAuthentication" "${ssh_settings[pubkeyauthentication]}"
    mst_security_record_finalize "${record_name}" "${started_ms}"
}

# Collect UFW installation and policy state.
mst_security_collect_ufw() {
    local check_id="${1:?check id required}"
    local record_name="${2:?record required}"
    local details_name="${3:?details required}"
    local errors_name="${4:?errors required}"
    local rows_name="${5:?rows required}"
    local -n record_ref="${record_name}"
    local started_ms label enabled_state incoming_policy outgoing_policy status severity
    local installed="false"

    mst_security_init_defaults
    started_ms="$(mst_mrrf_now_epoch_ms)"
    label="$(mst_security_check_label "${check_id}")"
    mst_security_record_init "${record_name}" "res_security.${check_id}" "${check_id}" "${label}" "config,command" "Derived from UFW configuration files."

    if mst_command_exists ufw || [[ -e "${MST_SECURITY_UFW_CONF_FILE}" ]] || [[ -e "${MST_SECURITY_UFW_DEFAULTS_FILE}" ]]; then
        installed="true"
    fi

    if [[ "${installed}" != "true" ]]; then
        mst_security_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "UFW is not installed." "dependency" "UFW_NOT_INSTALLED" "UFW command and configuration files were not found."
        mst_security_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    enabled_state="$(mst_security_read_assignment "${MST_SECURITY_UFW_CONF_FILE}" "ENABLED" || true)"
    incoming_policy="$(mst_security_read_assignment "${MST_SECURITY_UFW_DEFAULTS_FILE}" "DEFAULT_INPUT_POLICY" || true)"
    outgoing_policy="$(mst_security_read_assignment "${MST_SECURITY_UFW_DEFAULTS_FILE}" "DEFAULT_OUTPUT_POLICY" || true)"

    if [[ -z "${enabled_state}" ]] || [[ -z "${incoming_policy}" ]] || [[ -z "${outgoing_policy}" ]]; then
        mst_security_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "UFW configuration could not be fully determined." "configuration" "UFW_CONFIG_INCOMPLETE" "UFW configuration files were missing or incomplete."
        mst_security_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    status="ok"
    severity="ok"
    if [[ "${enabled_state,,}" != "yes" ]]; then
        status="warn"
        severity="warning"
    fi
    case "${incoming_policy^^}" in
        ACCEPT|ALLOW)
            status="warn"
            severity="warning"
            ;;
    esac

    record_ref[status]="${status}"
    record_ref[severity]="${severity}"
    record_ref[summary]="UFW is installed with ENABLED=${enabled_state}, incoming=${incoming_policy}, outgoing=${outgoing_policy}."

    mst_security_add_detail "${details_name}" "installed" "Installed" "boolean" "true" "" "false"
    mst_security_add_detail "${details_name}" "enabled" "Enabled" "string" "${enabled_state,,}" "" "false"
    mst_security_add_detail "${details_name}" "default_incoming_policy" "Default Incoming Policy" "string" "${incoming_policy}" "" "false"
    mst_security_add_detail "${details_name}" "default_outgoing_policy" "Default Outgoing Policy" "string" "${outgoing_policy}" "" "false"
    mst_security_add_row "${rows_name}" "Installed" "true"
    mst_security_add_row "${rows_name}" "Enabled" "${enabled_state,,}"
    mst_security_add_row "${rows_name}" "Default Incoming" "${incoming_policy}"
    mst_security_add_row "${rows_name}" "Default Outgoing" "${outgoing_policy}"
    mst_security_record_finalize "${record_name}" "${started_ms}"
}

# Collect Fail2Ban installation and jail state.
mst_security_collect_fail2ban() {
    local check_id="${1:?check id required}"
    local record_name="${2:?record required}"
    local details_name="${3:?details required}"
    local errors_name="${4:?errors required}"
    local rows_name="${5:?rows required}"
    local -n record_ref="${record_name}"
    local started_ms label resolved_unit state_output
    local active_state enabled_state result_state jail_count status severity fail2ban_output
    local -A state_map=()

    mst_security_init_defaults
    started_ms="$(mst_mrrf_now_epoch_ms)"
    label="$(mst_security_check_label "${check_id}")"
    mst_security_record_init "${record_name}" "res_security.${check_id}" "${check_id}" "${label}" "systemd,command" "Derived from systemd unit properties and fail2ban-client status."

    resolved_unit="$(mst_security_resolve_unit "${MST_SECURITY_FAIL2BAN_SERVICE_CANDIDATES}")" || {
        mst_security_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "Fail2Ban is not installed." "dependency" "FAIL2BAN_NOT_INSTALLED" "No configured Fail2Ban systemd unit was found."
        mst_security_record_finalize "${record_name}" "${started_ms}"
        return 0
    }

    state_output="$(mst_security_unit_state "${resolved_unit}")"
    if [[ "${state_output}" == error=* ]]; then
        mst_security_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "Fail2Ban state could not be determined." "unknown" "SYSTEMCTL_SHOW_FAILED" "${state_output#error=}"
        mst_security_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    while IFS='=' read -r key value; do
        state_map["${key}"]="${value}"
    done <<< "${state_output}"
    active_state="${state_map[active]:-unknown}"
    enabled_state="${state_map[enabled]:-unknown}"
    result_state="${state_map[result]:-unknown}"

    if [[ "${result_state}" == "failed" ]] || [[ "${active_state}" == "failed" ]]; then
        status="critical"
        severity="critical"
    elif [[ "${active_state}" != "active" ]] || [[ "${enabled_state}" == "disabled" ]]; then
        status="warn"
        severity="warning"
    else
        status="ok"
        severity="ok"
    fi

    jail_count=""
    if mst_command_exists fail2ban-client; then
        fail2ban_output="$(mst_security_fail2ban_status_output 2>/dev/null || true)"
        jail_count="$(mst_security_fail2ban_jail_count "${fail2ban_output}" || true)"
    fi

    record_ref[status]="${status}"
    record_ref[severity]="${severity}"
    record_ref[target]="${resolved_unit}"
    record_ref[summary]="Fail2Ban is ${active_state} and ${enabled_state}."

    mst_security_add_service_details "${details_name}" "${rows_name}" "${resolved_unit}" "${active_state}" "${enabled_state}"
    if [[ -n "${jail_count}" ]]; then
        mst_security_add_detail "${details_name}" "active_jails" "Active Jails" "integer" "${jail_count}" "" "false"
        mst_security_add_row "${rows_name}" "Active Jails" "${jail_count}"
        record_ref[summary]="Fail2Ban is ${active_state} and ${enabled_state} with ${jail_count} active jails."
    else
        mst_security_add_detail "${details_name}" "active_jails" "Active Jails" "null" "null" "" "false"
        mst_security_add_row "${rows_name}" "Active Jails" "n/a"
    fi
    mst_security_record_finalize "${record_name}" "${started_ms}"
}

# Collect unattended-upgrades presence and enablement.
mst_security_collect_unattended_upgrades() {
    local check_id="${1:?check id required}"
    local record_name="${2:?record required}"
    local details_name="${3:?details required}"
    local errors_name="${4:?errors required}"
    local rows_name="${5:?rows required}"
    local -n record_ref="${record_name}"
    local started_ms label enabled_value status severity installed="false"

    mst_security_init_defaults
    started_ms="$(mst_mrrf_now_epoch_ms)"
    label="$(mst_security_check_label "${check_id}")"
    mst_security_record_init "${record_name}" "res_security.${check_id}" "${check_id}" "${label}" "config,command" "Derived from unattended-upgrades package presence and APT periodic configuration."

    if mst_command_exists unattended-upgrade || [[ -e "${MST_SECURITY_AUTO_UPGRADES_FILE}" ]]; then
        installed="true"
    fi

    if [[ "${installed}" != "true" ]]; then
        mst_security_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "unattended-upgrades is not installed." "dependency" "UNATTENDED_UPGRADES_NOT_INSTALLED" "unattended-upgrade command and configuration file were not found."
        mst_security_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    enabled_value="$(mst_security_read_apt_value "${MST_SECURITY_AUTO_UPGRADES_FILE}" "APT::Periodic::Unattended-Upgrade" || true)"
    if [[ -z "${enabled_value}" ]]; then
        mst_security_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "Automatic security update state could not be determined." "configuration" "AUTO_UPGRADES_CONFIG_MISSING" "APT periodic unattended-upgrades setting was not found."
        mst_security_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    status="ok"
    severity="ok"
    if [[ "${enabled_value}" != "1" ]]; then
        status="warn"
        severity="warning"
    fi

    record_ref[status]="${status}"
    record_ref[severity]="${severity}"
    record_ref[summary]="Automatic security updates are installed and configured as ${enabled_value}."

    mst_security_add_detail "${details_name}" "installed" "Installed" "boolean" "true" "" "false"
    mst_security_add_detail "${details_name}" "enabled" "Enabled" "boolean" "$([[ "${enabled_value}" == "1" ]] && printf 'true' || printf 'false')" "" "false"
    mst_security_add_row "${rows_name}" "Installed" "true"
    mst_security_add_row "${rows_name}" "Enabled" "$([[ "${enabled_value}" == "1" ]] && printf 'true' || printf 'false')"
    mst_security_record_finalize "${record_name}" "${started_ms}"
}

# Collect time synchronization state.
mst_security_collect_time_sync() {
    local check_id="${1:?check id required}"
    local record_name="${2:?record required}"
    local details_name="${3:?details required}"
    local errors_name="${4:?errors required}"
    local rows_name="${5:?rows required}"
    local -n record_ref="${record_name}"
    local started_ms label resolved_unit state_output timedate_output
    local active_state enabled_state ntp_sync clock_sync status severity
    local -A state_map=()
    local -A time_map=()

    mst_security_init_defaults
    started_ms="$(mst_mrrf_now_epoch_ms)"
    label="$(mst_security_check_label "${check_id}")"
    mst_security_record_init "${record_name}" "res_security.${check_id}" "${check_id}" "${label}" "systemd,command" "Derived from systemd time synchronization properties."

    resolved_unit="$(mst_security_resolve_unit "${MST_SECURITY_TIMESYNC_SERVICE_CANDIDATES}")" || resolved_unit=""

    if [[ -n "${resolved_unit}" ]]; then
        state_output="$(mst_security_unit_state "${resolved_unit}")"
        if [[ "${state_output}" != error=* ]]; then
            while IFS='=' read -r key value; do
                state_map["${key}"]="${value}"
            done <<< "${state_output}"
            active_state="${state_map[active]:-unknown}"
            enabled_state="${state_map[enabled]:-unknown}"
        fi
    fi

    if ! mst_command_exists timedatectl; then
        mst_security_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "timedatectl is not available." "dependency" "TIMEDATECTL_NOT_AVAILABLE" "timedatectl command was not found."
        mst_security_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    timedate_output="$(mst_security_timedatectl_show 2>&1 || true)"
    if [[ "${timedate_output}" != *"NTPSynchronized="* ]] && [[ "${timedate_output}" != *"SystemClockSynchronized="* ]]; then
        mst_security_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "Time synchronization state could not be determined." "unknown" "TIMEDATECTL_SHOW_FAILED" "$(mst_mrrf_sanitize_text "${timedate_output}" 200)"
        mst_security_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    while IFS='=' read -r key value; do
        time_map["${key}"]="${value}"
    done <<< "${timedate_output}"
    ntp_sync="${time_map[NTPSynchronized]:-unknown}"
    clock_sync="${time_map[SystemClockSynchronized]:-unknown}"

    if [[ "${ntp_sync}" == "yes" ]] || [[ "${clock_sync}" == "yes" ]]; then
        status="ok"
        severity="ok"
    else
        status="warn"
        severity="warning"
    fi

    record_ref[status]="${status}"
    record_ref[severity]="${severity}"
    record_ref[target]="${resolved_unit:-timedatectl}"
    record_ref[summary]="Time synchronization reports NTPSynchronized=${ntp_sync}, SystemClockSynchronized=${clock_sync}."

    mst_security_add_detail "${details_name}" "service_name" "Time Sync Service" "string" "${resolved_unit:-unknown}" "" "false"
    mst_security_add_detail "${details_name}" "service_active" "Service Active" "string" "${active_state:-unknown}" "" "false"
    mst_security_add_detail "${details_name}" "service_enabled" "Service Enabled" "string" "${enabled_state:-unknown}" "" "false"
    mst_security_add_detail "${details_name}" "ntp_synchronized" "NTPSynchronized" "string" "${ntp_sync}" "" "false"
    mst_security_add_detail "${details_name}" "system_clock_synchronized" "SystemClockSynchronized" "string" "${clock_sync}" "" "false"
    mst_security_add_row "${rows_name}" "Service" "${resolved_unit:-unknown}"
    mst_security_add_row "${rows_name}" "Active" "${active_state:-unknown}"
    mst_security_add_row "${rows_name}" "Enabled" "${enabled_state:-unknown}"
    mst_security_add_row "${rows_name}" "NTPSynchronized" "${ntp_sync}"
    mst_security_add_row "${rows_name}" "SystemClockSynchronized" "${clock_sync}"
    mst_security_record_finalize "${record_name}" "${started_ms}"
}
