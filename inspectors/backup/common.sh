#!/usr/bin/env bash
# Shared helpers for the backup module.

# Apply default configuration for backup collectors.
mst_backup_init_defaults() {
    export MST_BACKUP_TARGETS="${MST_BACKUP_TARGETS:-}"
    export MST_BACKUP_TIMEOUT_SECONDS="${MST_BACKUP_TIMEOUT_SECONDS:-${MST_TIMEOUT_SECONDS:-${MST_DEFAULT_TIMEOUT_SECONDS}}}"
}

# Normalize one boolean-like flag to true or false.
mst_backup_normalize_boolean() {
    case "${1:-}" in
        1|yes|true) printf 'true' ;;
        *) printf 'false' ;;
    esac
}

# Return the configured backup target catalog in normalized form.
mst_backup_targets_catalog() {
    local spec="${MST_BACKUP_TARGETS:-}"
    local entry trimmed name target_type location expected_frequency maximum_age_hours minimum_size_mb enabled
    local old_ifs="${IFS}"

    [[ -z "${spec}" ]] && return 0
    IFS=';'
    for entry in ${spec}; do
        trimmed="${entry#"${entry%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -n "${trimmed}" ]] || continue
        IFS='|' read -r name target_type location expected_frequency maximum_age_hours minimum_size_mb enabled <<< "${trimmed}"
        [[ -n "${enabled:-}" ]] || enabled="true"
        printf '%s|%s|%s|%s|%s|%s|%s\n' \
            "${name}" \
            "${target_type}" \
            "${location}" \
            "${expected_frequency}" \
            "${maximum_age_hours}" \
            "${minimum_size_mb}" \
            "$(mst_backup_normalize_boolean "${enabled}")"
    done
    IFS="${old_ifs}"
}

# Create a stable result identifier fragment from a backup target name.
mst_backup_result_suffix() {
    local name="${1:?name required}"
    local lowered
    lowered="$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]')"
    lowered="$(printf '%s' "${lowered}" | tr -cs 'a-z0-9' '_')"
    lowered="${lowered##_}"
    lowered="${lowered%%_}"
    printf '%s' "${lowered:-target}"
}

# Return success if a local path exists.
mst_backup_target_exists() {
    [[ -e "${1:-}" ]]
}

# Return success if a local path is readable metadata-wise.
mst_backup_target_readable() {
    [[ -r "${1:-}" ]]
}

# Return success if a local path is directory searchable.
mst_backup_directory_accessible() {
    [[ -d "${1:-}" ]] && [[ -x "${1:-}" ]] && [[ -r "${1:-}" ]]
}

# Return type|size|mtime_epoch for one local path.
mst_backup_local_stat() {
    local path="${1:?path required}"
    local item_type="file"
    [[ -d "${path}" ]] && item_type="directory"
    printf '%s|%s|%s' "${item_type}" "$(stat -c '%s' -- "${path}")" "$(stat -c '%Y' -- "${path}")"
}

# Return basename|fullpath|size|mtime_epoch for the newest item in one directory.
mst_backup_latest_in_directory() {
    local directory_path="${1:?directory required}"
    local latest_path=""
    local candidate_path candidate_time latest_time=0

    while IFS= read -r -d '' candidate_path; do
        candidate_time="$(stat -c '%Y' -- "${candidate_path}")" || continue
        if [[ -z "${latest_path}" ]] || (( candidate_time > latest_time )); then
            latest_path="${candidate_path}"
            latest_time="${candidate_time}"
        fi
    done < <(find "${directory_path}" -mindepth 1 -maxdepth 1 -print0 2>/dev/null)

    [[ -n "${latest_path}" ]] || return 1
    printf '%s|%s|%s|%s' \
        "$(basename -- "${latest_path}")" \
        "${latest_path}" \
        "$(stat -c '%s' -- "${latest_path}")" \
        "${latest_time}"
}

# Return basename|fullpath|size|mtime_epoch for one local file target.
mst_backup_file_metadata() {
    local file_path="${1:?file path required}"
    printf '%s|%s|%s|%s' \
        "$(basename -- "${file_path}")" \
        "${file_path}" \
        "$(stat -c '%s' -- "${file_path}")" \
        "$(stat -c '%Y' -- "${file_path}")"
}

# Return current epoch seconds.
mst_backup_now_epoch() {
    date -u '+%s'
}

# Convert epoch seconds to UTC timestamp.
mst_backup_epoch_to_utc() {
    local epoch_seconds="${1:?epoch required}"
    date -u -d "@${epoch_seconds}" '+%Y-%m-%dT%H:%M:%SZ'
}

# Convert bytes to integer mebibytes.
mst_backup_bytes_to_mib() {
    local bytes_value="${1:?bytes required}"
    printf '%s' "$(( bytes_value / 1048576 ))"
}

# Return age in integer hours from a modification epoch.
mst_backup_age_hours() {
    local modified_epoch="${1:?epoch required}"
    local now_epoch
    now_epoch="$(mst_backup_now_epoch)"
    printf '%s' "$(( (now_epoch - modified_epoch) / 3600 ))"
}

# Return success if one location looks like an rclone remote.
mst_backup_rclone_remote_name() {
    local location="${1:?location required}"
    [[ "${location}" == *:* ]] || return 1
    printf '%s' "${location%%:*}"
}

# Return success if rclone configuration contains the named remote.
mst_backup_rclone_remote_configured() {
    local remote_name="${1:?remote name required}"
    local output line

    output="$(mst_exec_capture_stdout "${MST_BACKUP_TIMEOUT_SECONDS}" rclone listremotes 2>/dev/null || true)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        [[ "${line}" == "${remote_name}:" ]] && return 0
    done <<< "${output}"
    return 1
}

# Run rclone lsjson for one remote target.
mst_backup_rclone_lsjson() {
    local location="${1:?location required}"
    mst_exec_capture_stdout "${MST_BACKUP_TIMEOUT_SECONDS}" rclone lsjson --recursive "${location}"
}

# Return name|size|modtime for the latest object in one lsjson payload.
mst_backup_rclone_latest_object() {
    local json_payload="${1:-}"
    local compact payload object best_name="" best_size="" best_modtime="" best_epoch=-1
    local name size modtime is_dir epoch

    compact="$(printf '%s' "${json_payload}" | tr -d '\n' | sed 's/^[[:space:]]*\[//; s/\][[:space:]]*$//; s/},{/}\n{/g')"
    while IFS= read -r object || [[ -n "${object}" ]]; do
        [[ -n "${object}" ]] || continue
        is_dir="$(printf '%s' "${object}" | sed -n 's/.*"IsDir"[[:space:]]*:[[:space:]]*\(true\|false\).*/\1/p')"
        [[ "${is_dir}" == "true" ]] && continue
        name="$(printf '%s' "${object}" | sed -n 's/.*"Name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
        [[ -n "${name}" ]] || name="$(printf '%s' "${object}" | sed -n 's/.*"Path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
        size="$(printf '%s' "${object}" | sed -n 's/.*"Size"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
        modtime="$(printf '%s' "${object}" | sed -n 's/.*"ModTime"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
        [[ -n "${name}" ]] || continue
        [[ -n "${modtime}" ]] || continue
        epoch="$(date -u -d "${modtime}" '+%s' 2>/dev/null || true)"
        [[ -n "${epoch}" ]] || continue
        if (( epoch > best_epoch )); then
            best_epoch="${epoch}"
            best_name="${name}"
            best_size="${size:-0}"
            best_modtime="${modtime}"
        fi
    done <<< "${compact}"

    [[ -n "${best_name}" ]] || return 1
    printf '%s|%s|%s' "${best_name}" "${best_size:-0}" "${best_modtime}"
}

# Detect hostname for aggregate documents.
mst_backup_detect_hostname() {
    local hostname_file="/proc/sys/kernel/hostname"
    if [[ -r "${hostname_file}" ]]; then
        tr -d '\n' < "${hostname_file}"
    else
        hostname 2>/dev/null || printf 'localhost'
    fi
}

# Initialize one backup MRRF1 record.
mst_backup_record_init() {
    local record_name="${1:?record required}"
    local result_id="${2:?result id required}"
    local target_name="${3:?target required}"
    local provenance="${4:?provenance required}"
    local -n record_ref="${record_name}"

    record_ref[result_id]="${result_id}"
    record_ref[module]="backup"
    record_ref[check]="backup_health"
    record_ref[target]="${target_name}"
    record_ref[status]="unknown"
    record_ref[severity]="unknown"
    record_ref[score]="null"
    record_ref[summary]="Backup observation unavailable."
    record_ref[source_list]="filesystem,stat,find,rclone"
    record_ref[provenance]="${provenance}"
    record_ref[privilege_requirement]="none"
    record_ref[redactions_present]="false"
}

# Finalize one backup record.
mst_backup_record_finalize() {
    local record_name="${1:?record required}"
    local started_ms="${2:?started required}"
    local finished_ms duration_ms
    local -n record_ref="${record_name}"

    finished_ms="$(mst_mrrf_now_epoch_ms)"
    duration_ms=$(( finished_ms - started_ms ))
    record_ref[duration_ms]="${duration_ms}"
    record_ref[observed_at]="$(mst_mrrf_now_utc)"
}

# Append one MRRF1 detail.
mst_backup_add_detail() {
    local details_name="${1:?details required}"
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
mst_backup_add_row() {
    local rows_name="${1:?rows required}"
    local label="${2:?label required}"
    local value="${3:-}"
    local -n rows_ref="${rows_name}"

    rows_ref+=("$(mst_mrrf_sanitize_text "${label}" 64)${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${value}" 200)")
}

# Append one MRRF1 error.
mst_backup_add_error() {
    local errors_name="${1:?errors required}"
    local category="${2:?category required}"
    local code="${3:?code required}"
    local message="${4:?message required}"
    local -n errors_ref="${errors_name}"

    errors_ref+=("$(mst_mrrf_pack_error "${category}" "${code}" "${message}")")
}

# Mark a backup record with a failure state.
mst_backup_mark_failure() {
    local record_name="${1:?record required}"
    local errors_name="${2:?errors required}"
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
    mst_backup_add_error "${errors_name}" "${error_category}" "${error_code}" "${error_message}"
}

# Build a generic internal failure record for collector isolation.
mst_backup_build_internal_failure_record() {
    local target_index="${1:?index required}"
    local name="${2:?name required}"
    local record_name="${3:?record required}"
    local details_name="${4:?details required}"
    local errors_name="${5:?errors required}"
    local message="${6:?message required}"
    local started_ms
    local -n details_ref="${details_name}"
    local -n errors_ref="${errors_name}"

    started_ms="$(mst_mrrf_now_epoch_ms)"
    details_ref=()
    errors_ref=()
    mst_backup_record_init "${record_name}" "res_backup.${target_index}.$(mst_backup_result_suffix "${name}")" "${name}" "Collector fallback path."
    mst_backup_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "${message}" "internal" "COLLECTOR_FAILURE" "${message}"
    mst_backup_record_finalize "${record_name}" "${started_ms}"
}

# Return the worst MRRF1 status from a status array.
mst_backup_worst_status() {
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
mst_backup_worst_severity() {
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

# Return the backup command exit code from record statuses.
mst_backup_report_exit_code() {
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
mst_backup_module_summary_json() {
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

# Collect one configured backup target.
mst_backup_collect_target() {
    local target_index="${1:?index required}"
    local name="${2:?name required}"
    local target_type="${3:?type required}"
    local location="${4:?location required}"
    local expected_frequency="${5:?frequency required}"
    local maximum_age_hours="${6:?max age required}"
    local minimum_size_mb="${7:?min size required}"
    local enabled="${8:?enabled required}"
    local record_name="${9:?record required}"
    local details_name="${10:?details required}"
    local errors_name="${11:?errors required}"
    local rows_name="${12:?rows required}"
    local started_ms target_exists accessible latest_name latest_path latest_size latest_mtime latest_age_hours
    local within_expected_age stale_detected destination_reachable file_readable minimum_size_bytes summary
    local remote_name remote_configured remote_reachable remote_payload remote_latest remote_modtime remote_epoch
    local status severity
    local -n record_ref="${record_name}"

    mst_backup_init_defaults
    started_ms="$(mst_mrrf_now_epoch_ms)"
    mst_backup_record_init "${record_name}" "res_backup.${target_index}.$(mst_backup_result_suffix "${name}")" "${name}" "Derived from local filesystem metadata and optional rclone lsjson metadata."

    if [[ "${enabled}" != "true" ]]; then
        mst_backup_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "${name} backup monitoring is disabled." "configuration" "BACKUP_DISABLED" "Backup target ${name} is disabled in configuration."
        mst_backup_add_detail "${details_name}" "backup_name" "Backup Name" "string" "${name}" "" "false"
        mst_backup_add_detail "${details_name}" "backup_type" "Backup Type" "string" "${target_type}" "" "false"
        mst_backup_add_detail "${details_name}" "configured_location" "Configured Location" "string" "${location}" "" "false"
        mst_backup_add_row "${rows_name}" "Name" "${name}"
        mst_backup_add_row "${rows_name}" "Type" "${target_type}"
        mst_backup_add_row "${rows_name}" "Location" "${location}"
        mst_backup_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    status="ok"
    severity="ok"
    target_exists="false"
    accessible="false"
    latest_name=""
    latest_path=""
    latest_size="0"
    latest_mtime=""
    latest_age_hours="0"
    within_expected_age="false"
    stale_detected="false"
    destination_reachable="false"
    file_readable="false"
    remote_configured="false"
    remote_reachable="false"
    minimum_size_bytes=$(( minimum_size_mb * 1048576 ))

    case "${target_type}" in
        local_directory)
            if mst_backup_target_exists "${location}"; then
                target_exists="true"
            fi
            if mst_backup_directory_accessible "${location}"; then
                accessible="true"
                destination_reachable="true"
                latest_path="$(mst_backup_latest_in_directory "${location}" 2>/dev/null || true)"
                if [[ -n "${latest_path}" ]]; then
                    IFS='|' read -r latest_name latest_path latest_size latest_mtime <<< "${latest_path}"
                    file_readable="true"
                else
                    status="critical"
                    severity="critical"
                    mst_backup_add_error "${errors_name}" "dependency" "BACKUP_MISSING" "No backup object was found in ${location}."
                fi
            fi
            ;;
        local_file)
            if mst_backup_target_exists "${location}"; then
                target_exists="true"
            fi
            if mst_backup_target_readable "${location}"; then
                accessible="true"
                destination_reachable="true"
                file_readable="true"
                IFS='|' read -r latest_name latest_path latest_size latest_mtime <<< "$(mst_backup_file_metadata "${location}")"
            fi
            ;;
        rclone_remote)
            if ! mst_command_exists rclone; then
                status="unavailable"
                severity="unknown"
                mst_backup_add_error "${errors_name}" "dependency" "RCLONE_UNAVAILABLE" "rclone command was not found for ${name}."
            else
                remote_name="$(mst_backup_rclone_remote_name "${location}" || true)"
                if [[ -n "${remote_name}" ]] && mst_backup_rclone_remote_configured "${remote_name}"; then
                    remote_configured="true"
                fi
                if [[ "${remote_configured}" != "true" ]]; then
                    status="critical"
                    severity="critical"
                    mst_backup_add_error "${errors_name}" "dependency" "RCLONE_REMOTE_NOT_CONFIGURED" "Configured rclone remote is not available for ${location}."
                else
                    remote_payload="$(mst_backup_rclone_lsjson "${location}" 2>/dev/null || true)"
                    if [[ -n "${remote_payload}" ]]; then
                        remote_reachable="true"
                        destination_reachable="true"
                        target_exists="true"
                        accessible="true"
                        remote_latest="$(mst_backup_rclone_latest_object "${remote_payload}" || true)"
                        if [[ -n "${remote_latest}" ]]; then
                            IFS='|' read -r latest_name latest_size remote_modtime <<< "${remote_latest}"
                            latest_mtime="$(date -u -d "${remote_modtime}" '+%s' 2>/dev/null || true)"
                            latest_path="${location}/${latest_name}"
                            file_readable="true"
                        else
                            status="critical"
                            severity="critical"
                            mst_backup_add_error "${errors_name}" "dependency" "BACKUP_MISSING" "No remote backup object metadata was found for ${location}."
                        fi
                    else
                        status="critical"
                        severity="critical"
                        mst_backup_add_error "${errors_name}" "network" "RCLONE_REMOTE_UNREACHABLE" "rclone could not read metadata for ${location}."
                    fi
                fi
            fi
            ;;
    esac

    if [[ "${target_exists}" != "true" ]]; then
        status="critical"
        severity="critical"
        mst_backup_add_error "${errors_name}" "dependency" "BACKUP_TARGET_MISSING" "Backup target ${location} does not exist."
    fi

    if [[ "${accessible}" != "true" ]] && [[ "${target_type}" != "rclone_remote" ]]; then
        status="critical"
        severity="critical"
        mst_backup_add_error "${errors_name}" "permission" "BACKUP_UNREADABLE" "Backup target ${location} is not accessible."
    fi

    if [[ -n "${latest_mtime}" ]] && [[ "${latest_mtime}" =~ ^[0-9]+$ ]]; then
        latest_age_hours="$(mst_backup_age_hours "${latest_mtime}")"
        if (( latest_age_hours <= maximum_age_hours )); then
            within_expected_age="true"
        else
            within_expected_age="false"
            stale_detected="true"
            if [[ "${status}" == "ok" ]]; then
                status="warn"
                severity="warning"
            fi
            mst_backup_add_error "${errors_name}" "warning" "BACKUP_STALE" "Latest backup for ${name} is older than ${maximum_age_hours} hours."
        fi
    fi

    if [[ "${file_readable}" == "true" ]] && [[ "${latest_size}" =~ ^[0-9]+$ ]] && (( latest_size < minimum_size_bytes )); then
        if [[ "${status}" == "ok" ]]; then
            status="warn"
            severity="warning"
        fi
        mst_backup_add_error "${errors_name}" "warning" "BACKUP_SIZE_BELOW_MINIMUM" "Latest backup for ${name} is smaller than ${minimum_size_mb} MiB."
    fi

    summary="${name} backup target looks healthy."
    if [[ "${status}" == "critical" ]]; then
        summary="${name} backup target has an error condition."
    elif [[ "${status}" == "warn" ]]; then
        summary="${name} backup target has warning conditions."
    elif [[ "${status}" == "unavailable" ]]; then
        summary="${name} backup monitoring is unavailable."
    fi

    record_ref[status]="${status}"
    record_ref[severity]="${severity}"
    record_ref[target]="${name}"
    record_ref[summary]="${summary}"

    mst_backup_add_detail "${details_name}" "backup_name" "Backup Name" "string" "${name}" "" "false"
    mst_backup_add_detail "${details_name}" "backup_type" "Backup Type" "string" "${target_type}" "" "false"
    mst_backup_add_detail "${details_name}" "configured_location" "Configured Location" "string" "${location}" "" "false"
    mst_backup_add_detail "${details_name}" "target_exists" "Target Exists" "boolean" "${target_exists}" "" "false"
    mst_backup_add_detail "${details_name}" "accessible" "Accessible" "boolean" "${accessible}" "" "false"
    if [[ -n "${latest_name}" ]]; then
        mst_backup_add_detail "${details_name}" "latest_backup_filename" "Latest Backup Filename" "string" "${latest_name}" "" "false"
    else
        mst_backup_add_detail "${details_name}" "latest_backup_filename" "Latest Backup Filename" "null" "null" "" "false"
    fi
    if [[ -n "${latest_mtime}" ]] && [[ "${latest_mtime}" =~ ^[0-9]+$ ]]; then
        mst_backup_add_detail "${details_name}" "last_modified_timestamp" "Last Modified" "string" "$(mst_backup_epoch_to_utc "${latest_mtime}")" "" "false"
        mst_backup_add_detail "${details_name}" "backup_age_hours" "Backup Age" "integer" "${latest_age_hours}" "hours" "false"
    else
        mst_backup_add_detail "${details_name}" "last_modified_timestamp" "Last Modified" "null" "null" "" "false"
        mst_backup_add_detail "${details_name}" "backup_age_hours" "Backup Age" "null" "null" "" "false"
    fi
    mst_backup_add_detail "${details_name}" "backup_size_mb" "Backup Size" "integer" "$(mst_backup_bytes_to_mib "${latest_size:-0}")" "MiB" "false"
    mst_backup_add_detail "${details_name}" "within_expected_age" "Within Expected Age" "boolean" "${within_expected_age}" "" "false"
    mst_backup_add_detail "${details_name}" "stale_backup_detected" "Stale Backup Detected" "boolean" "${stale_detected}" "" "false"
    mst_backup_add_detail "${details_name}" "destination_reachable" "Destination Reachable" "boolean" "${destination_reachable}" "" "false"
    mst_backup_add_detail "${details_name}" "file_readable" "File Readable" "boolean" "${file_readable}" "" "false"
    if [[ "${target_type}" == "rclone_remote" ]]; then
        mst_backup_add_detail "${details_name}" "remote_configured" "Remote Configured" "boolean" "${remote_configured}" "" "false"
        mst_backup_add_detail "${details_name}" "remote_reachable" "Remote Reachable" "boolean" "${remote_reachable}" "" "false"
    fi

    mst_backup_add_row "${rows_name}" "Name" "${name}"
    mst_backup_add_row "${rows_name}" "Type" "${target_type}"
    mst_backup_add_row "${rows_name}" "Location" "${location}"
    mst_backup_add_row "${rows_name}" "Exists" "${target_exists}"
    mst_backup_add_row "${rows_name}" "Accessible" "${accessible}"
    mst_backup_add_row "${rows_name}" "Latest Backup" "${latest_name:-n/a}"
    mst_backup_add_row "${rows_name}" "Last Modified" "$([[ -n "${latest_mtime}" ]] && mst_backup_epoch_to_utc "${latest_mtime}" || printf 'n/a')"
    mst_backup_add_row "${rows_name}" "Backup Age" "$([[ -n "${latest_mtime}" ]] && printf '%s hours' "${latest_age_hours}" || printf 'n/a')"
    mst_backup_add_row "${rows_name}" "Backup Size" "$(printf '%s MiB' "$(mst_backup_bytes_to_mib "${latest_size:-0}")")"
    mst_backup_add_row "${rows_name}" "Within Expected Age" "${within_expected_age}"
    mst_backup_add_row "${rows_name}" "Stale Backup" "${stale_detected}"
    mst_backup_add_row "${rows_name}" "Destination Reachable" "${destination_reachable}"
    mst_backup_add_row "${rows_name}" "File Readable" "${file_readable}"
    if [[ "${target_type}" == "rclone_remote" ]]; then
        mst_backup_add_row "${rows_name}" "Remote Configured" "${remote_configured}"
        mst_backup_add_row "${rows_name}" "Remote Reachable" "${remote_reachable}"
    fi
    mst_backup_record_finalize "${record_name}" "${started_ms}"
}
