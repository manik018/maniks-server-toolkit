#!/usr/bin/env bash
# Shared helpers for the health module collectors.

# Apply default data-source paths for health collectors.
mst_health_init_data_sources() {
    export MST_HEALTH_PROC_DIR="${MST_HEALTH_PROC_DIR:-/proc}"
    export MST_HEALTH_OS_RELEASE_FILE="${MST_HEALTH_OS_RELEASE_FILE:-/etc/os-release}"
    export MST_HEALTH_MOUNTS_FILE="${MST_HEALTH_MOUNTS_FILE:-${MST_HEALTH_PROC_DIR}/self/mounts}"
    export MST_HEALTH_CPU_SAMPLE_SLEEP="${MST_HEALTH_CPU_SAMPLE_SLEEP:-0.2}"
    export MST_HEALTH_CPU_WARN_PERCENT="${MST_HEALTH_CPU_WARN_PERCENT:-80}"
    export MST_HEALTH_CPU_ERROR_PERCENT="${MST_HEALTH_CPU_ERROR_PERCENT:-95}"
    export MST_HEALTH_MEMORY_WARN_PERCENT="${MST_HEALTH_MEMORY_WARN_PERCENT:-85}"
    export MST_HEALTH_MEMORY_ERROR_PERCENT="${MST_HEALTH_MEMORY_ERROR_PERCENT:-95}"
    export MST_HEALTH_DISK_WARN_PERCENT="${MST_HEALTH_DISK_WARN_PERCENT:-85}"
    export MST_HEALTH_DISK_ERROR_PERCENT="${MST_HEALTH_DISK_ERROR_PERCENT:-95}"
}

# Read one file into stdout if it is available.
mst_health_read_file() {
    local file_path="${1:?file path required}"
    [[ -r "${file_path}" ]] || return 1
    cat -- "${file_path}"
}

# Read the first matching key from a colon-separated procfs file.
mst_health_read_colon_value() {
    local file_path="${1:?file path required}"
    local key_name="${2:?key name required}"
    local line key value

    while IFS= read -r line || [[ -n "${line}" ]]; do
        key="${line%%:*}"
        if [[ "${key}" == "${key_name}" ]]; then
            value="${line#*:}"
            value="${value#"${value%%[![:space:]]*}"}"
            printf '%s' "${value}"
            return 0
        fi
    done < "${file_path}"
    return 1
}

# Convert kibibytes to mebibytes as an integer.
mst_health_kib_to_mib() {
    local kib_value="${1:?KiB value required}"
    printf '%s' "$(( kib_value / 1024 ))"
}

# Return a factual status and severity pair from percentage thresholds.
mst_health_threshold_status() {
    local percent="${1:?percent required}"
    local warn_threshold="${2:?warn threshold required}"
    local error_threshold="${3:?error threshold required}"

    if (( percent >= error_threshold )); then
        printf 'critical|critical'
    elif (( percent >= warn_threshold )); then
        printf 'warn|warning'
    else
        printf 'ok|ok'
    fi
}

# Initialize a standard health MRRF1 record shell object.
mst_health_record_init() {
    local record_name="${1:?record name required}"
    local result_id="${2:?result id required}"
    local check_name="${3:?check name required}"
    local target_name="${4:?target required}"
    local source_list="${5:?source list required}"
    local provenance="${6:?provenance required}"
    local -n record_ref="${record_name}"

    record_ref[result_id]="${result_id}"
    record_ref[module]="health"
    record_ref[check]="${check_name}"
    record_ref[target]="${target_name}"
    record_ref[status]="unknown"
    record_ref[severity]="unknown"
    record_ref[score]="null"
    record_ref[summary]="Observation unavailable."
    record_ref[source_list]="${source_list}"
    record_ref[provenance]="${provenance}"
    record_ref[privilege_requirement]="none"
    record_ref[redactions_present]="false"
}

# Finalize one collector result with duration and timestamp metadata.
mst_health_record_finalize() {
    local record_name="${1:?record name required}"
    local started_ms="${2:?started ms required}"
    local finished_ms
    local duration_ms
    local -n record_ref="${record_name}"

    finished_ms="$(mst_mrrf_now_epoch_ms)"
    duration_ms=$(( finished_ms - started_ms ))
    record_ref[duration_ms]="${duration_ms}"
    record_ref[observed_at]="$(mst_mrrf_now_utc)"
}

# Append one MRRF1 detail to a detail array.
mst_health_add_detail() {
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
mst_health_add_row() {
    local rows_name="${1:?rows array name required}"
    local label="${2:?label required}"
    local value="${3:-}"
    local -n rows_ref="${rows_name}"

    rows_ref+=("$(mst_mrrf_sanitize_text "${label}" 64)${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${value}" 200)")
}

# Append one MRRF1 error to an error array.
mst_health_add_error() {
    local errors_name="${1:?errors array name required}"
    local category="${2:?category required}"
    local code="${3:?code required}"
    local message="${4:?message required}"
    local -n errors_ref="${errors_name}"

    errors_ref+=("$(mst_mrrf_pack_error "${category}" "${code}" "${message}")")
}

# Return the appropriate error category for an unreadable source path.
mst_health_source_error_category() {
    local source_path="${1:?source path required}"
    if [[ -e "${source_path}" ]] && [[ ! -r "${source_path}" ]]; then
        printf 'permission'
    else
        printf 'dependency'
    fi
}

# Build a consistent unavailable or unknown record for collector failures.
mst_health_mark_failure() {
    local record_name="${1:?record name required}"
    local errors_name="${2:?errors array name required}"
    local status="${3:?status required}"
    local severity="${4:?severity required}"
    local summary="${5:?summary required}"
    local error_category="${6:?error category required}"
    local error_code="${7:?error code required}"
    local error_message="${8:?error message required}"
    local -n record_ref="${record_name}"

    record_ref[status]="${status}"
    record_ref[severity]="${severity}"
    record_ref[summary]="${summary}"
    mst_health_add_error "${errors_name}" "${error_category}" "${error_code}" "${error_message}"
}

# Build a generic internal failure record for collector isolation.
mst_health_build_internal_failure_record() {
    local collector_id="${1:?collector id required}"
    local record_name="${2:?record name required}"
    local details_name="${3:?details array name required}"
    local errors_name="${4:?errors array name required}"
    local message="${5:?message required}"
    local started_ms
    local -n record_ref="${record_name}"
    local -n details_ref="${details_name}"
    local -n errors_ref="${errors_name}"

    started_ms="$(mst_mrrf_now_epoch_ms)"
    details_ref=()
    errors_ref=()
    mst_health_record_init "${record_name}" "res_health.${collector_id}" "${collector_id}" "localhost" "derived" "Collector fallback path."
    mst_health_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "${message}" "internal" "COLLECTOR_FAILURE" "${message}"
    mst_health_record_finalize "${record_name}" "${started_ms}"
}

# Convert a percentage status array to one overall status.
mst_health_worst_status() {
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

# Convert a severity array to one overall severity.
mst_health_worst_severity() {
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

# Return the health command exit code from collector statuses.
mst_health_report_exit_code() {
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

# Build one module summary JSON object for the aggregate report.
mst_health_module_summary_json() {
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

# Detect the current hostname with procfs-first behavior.
mst_health_detect_hostname() {
    local hostname_file="${MST_HEALTH_PROC_DIR}/sys/kernel/hostname"
    if [[ -r "${hostname_file}" ]]; then
        tr -d '\n' < "${hostname_file}"
    else
        hostname 2>/dev/null || printf 'localhost'
    fi
}

# Format a mebibyte value for terminal output.
mst_health_format_mib() {
    local value="${1:?MiB value required}"
    if (( value >= 1024 )); then
        printf '%s GiB' "$(( value / 1024 ))"
    else
        printf '%s MiB' "${value}"
    fi
}

# Format a raw duration in seconds for terminal output.
mst_health_format_duration_seconds() {
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

# Decode mount-escaped fields from procfs mount data.
mst_health_decode_mount_field() {
    local value="${1:-}"
    value="${value//\\040/ }"
    value="${value//\\011/$'\t'}"
    value="${value//\\012/ }"
    printf '%s' "${value}"
}
