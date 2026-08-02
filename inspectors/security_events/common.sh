#!/usr/bin/env bash
# Shared helpers for the security events module.

if [[ -n "${MST_SECURITY_EVENTS_COMMON_LOADED:-}" ]]; then
    return
fi
readonly MST_SECURITY_EVENTS_COMMON_LOADED=1

# Limit the first scan after deployment or rotation to avoid a historical spike.
readonly MST_SECURITY_EVENTS_FRESH_SCAN_MAX_BYTES=1048576

mst_security_events_init_defaults() {
    export MST_SECURITY_EVENTS_AUTH_LOG_PATH="${MST_SECURITY_EVENTS_AUTH_LOG_PATH:-/var/log/auth.log}"
    export MST_SECURITY_EVENTS_SSH_FAILED_WARN_COUNT="${MST_SECURITY_EVENTS_SSH_FAILED_WARN_COUNT:-10}"
    export MST_SECURITY_EVENTS_SSH_ROOT_ATTEMPT_WARN_COUNT="${MST_SECURITY_EVENTS_SSH_ROOT_ATTEMPT_WARN_COUNT:-1}"
    export MST_SECURITY_EVENTS_TIMEOUT_SECONDS="${MST_SECURITY_EVENTS_TIMEOUT_SECONDS:-${MST_TIMEOUT_SECONDS:-${MST_DEFAULT_TIMEOUT_SECONDS}}}"
}

mst_security_events_cursor_path() {
    local cursor_dir cursor_path
    cursor_dir="${MST_STATE_DIR:?state dir required}/security_events"
    cursor_dir="$(mst_fs_validate_runtime_directory "${cursor_dir}")" || return 1
    mst_fs_ensure_directory "${cursor_dir}" || return 1
    cursor_path="${cursor_dir}/auth_log.cursor"
    mst_fs_validate_runtime_file_path "${cursor_path}"
}

mst_security_events_read_cursor() {
    local cursor_path="${1:?cursor path required}"
    local cursor_value stored_inode stored_offset
    [[ -f "${cursor_path}" ]] && [[ -r "${cursor_path}" ]] || return 1
    cursor_value="$(< "${cursor_path}")"
    IFS='|' read -r stored_inode stored_offset <<< "${cursor_value}"
    [[ "${stored_inode}" =~ ^[0-9]+$ ]] || return 1
    [[ "${stored_offset}" =~ ^[0-9]+$ ]] || return 1
    printf '%s|%s' "${stored_inode}" "${stored_offset}"
}

mst_security_events_read_new_bytes() {
    local log_path="${1:?log path required}"
    local cursor_path="${2:?cursor path required}"
    local file_inode file_size stored_inode stored_offset start_offset
    local cursor_value fresh_start=false

    file_inode="$(stat -c '%i' -- "${log_path}")" || return 1
    file_size="$(stat -c '%s' -- "${log_path}")" || return 1
    cursor_value="$(mst_security_events_read_cursor "${cursor_path}" || true)"
    if [[ -z "${cursor_value}" ]]; then
        fresh_start=true
    else
        IFS='|' read -r stored_inode stored_offset <<< "${cursor_value}"
        if [[ "${stored_inode}" != "${file_inode}" ]] || (( 10#${stored_offset} > 10#${file_size} )); then
            fresh_start=true
        fi
    fi

    if [[ "${fresh_start}" == "true" ]]; then
        start_offset=$(( file_size > MST_SECURITY_EVENTS_FRESH_SCAN_MAX_BYTES ? file_size - MST_SECURITY_EVENTS_FRESH_SCAN_MAX_BYTES : 0 ))
    else
        start_offset="${stored_offset}"
    fi

    MST_SECURITY_EVENTS_READ_PAYLOAD=""
    if (( file_size != start_offset )); then
        MST_SECURITY_EVENTS_READ_PAYLOAD="$(tail -c +$(( start_offset + 1 )) -- "${log_path}")" || return 1
    fi
    MST_SECURITY_EVENTS_READ_INODE="${file_inode}"
    MST_SECURITY_EVENTS_READ_SIZE="${file_size}"
    MST_SECURITY_EVENTS_READ_FRESH_START="${fresh_start}"
}

mst_security_events_parse_lines() {
    local payload="${1:-}"
    awk '
        /Failed password for/ { failed++ }
        /Accepted (publickey|password) for/ { accepted++ }
        /for (invalid user )?root([[:space:]]|$)/ { root++ }
        { lines++ }
        END { printf "%d\037%d\037%d\037%d", failed + 0, accepted + 0, root + 0, lines + 0 }
    ' <<< "${payload}"
}

mst_security_events_add_detail() {
    local details_name="${1:?details required}"
    local key_name="${2:?key required}"
    local label="${3:?label required}"
    local value="${4:?value required}"
    local -n details_ref="${details_name}"
    details_ref+=("$(mst_mrrf_pack_detail "${key_name}" "${label}" "integer" "${value}" "" "false")")
}

mst_security_events_add_error() {
    local errors_name="${1:?errors required}"
    local category="${2:?category required}"
    local code="${3:?code required}"
    local message="${4:?message required}"
    local -n errors_ref="${errors_name}"
    errors_ref+=("$(mst_mrrf_pack_error "${category}" "${code}" "${message}")")
}

mst_security_events_collect() {
    local record_name="${1:?record name required}"
    local details_name="${2:?details array name required}"
    local errors_name="${3:?errors array name required}"
    local started_ms log_path cursor_path read_result payload file_inode file_size fresh_start
    local failed_count accepted_count root_count lines_scanned status summary parsed
    local -n record_ref="${record_name}"
    local -n details_ref="${details_name}"
    local -n errors_ref="${errors_name}"

    mst_security_events_init_defaults
    started_ms="$(mst_mrrf_now_epoch_ms)"
    record_ref=()
    details_ref=()
    errors_ref=()
    record_ref[result_id]="res_security_events.ssh_login_activity"
    record_ref[module]="security_events"
    record_ref[check]="ssh_login_activity"
    record_ref[target]="${MST_SECURITY_EVENTS_AUTH_LOG_PATH}"
    record_ref[status]="unavailable"
    record_ref[severity]="unknown"
    record_ref[score]="null"
    record_ref[source_list]="auth.log,awk,stat"
    record_ref[provenance]="Incremental SSH authentication activity from the configured auth log."
    record_ref[privilege_requirement]="none"
    record_ref[redactions_present]="false"

    log_path="${MST_SECURITY_EVENTS_AUTH_LOG_PATH}"
    if [[ ! -f "${log_path}" ]] || [[ ! -r "${log_path}" ]]; then
        record_ref[summary]="SSH auth log is missing or unreadable."
        mst_security_events_add_error "${errors_name}" "dependency" "AUTH_LOG_UNAVAILABLE" "The configured SSH auth log is missing or unreadable."
    else
        cursor_path="$(mst_security_events_cursor_path 2>/dev/null || true)"
        if [[ -z "${cursor_path}" ]]; then
            record_ref[summary]="SSH auth log cursor state is unavailable."
            mst_security_events_add_error "${errors_name}" "state" "AUTH_LOG_CURSOR_UNAVAILABLE" "The security events cursor path could not be prepared."
        elif ! mst_security_events_read_new_bytes "${log_path}" "${cursor_path}"; then
            record_ref[summary]="SSH auth log could not be read."
            mst_security_events_add_error "${errors_name}" "dependency" "AUTH_LOG_READ_FAILED" "The configured SSH auth log could not be read."
        else
            payload="${MST_SECURITY_EVENTS_READ_PAYLOAD}"
            file_inode="${MST_SECURITY_EVENTS_READ_INODE}"
            file_size="${MST_SECURITY_EVENTS_READ_SIZE}"
            fresh_start="${MST_SECURITY_EVENTS_READ_FRESH_START}"
            parsed="$(mst_security_events_parse_lines "${payload}")"
            IFS=$'\037' read -r failed_count accepted_count root_count lines_scanned <<< "${parsed}"
            status="ok"
            if (( 10#${failed_count} > 10#${MST_SECURITY_EVENTS_SSH_FAILED_WARN_COUNT} )) || (( 10#${root_count} >= 10#${MST_SECURITY_EVENTS_SSH_ROOT_ATTEMPT_WARN_COUNT} )); then
                status="warn"
            fi
            record_ref[status]="${status}"
            record_ref[severity]="${status}"
            summary="${failed_count} failed SSH login(s), ${accepted_count} accepted, ${root_count} root login attempts since last check."
            record_ref[summary]="${summary}"
            mst_security_events_add_detail "${details_name}" "ssh_failed_count" "Failed SSH Logins" "${failed_count}"
            mst_security_events_add_detail "${details_name}" "ssh_accepted_count" "Accepted SSH Logins" "${accepted_count}"
            mst_security_events_add_detail "${details_name}" "ssh_root_attempt_count" "Root Login Attempts" "${root_count}"
            mst_security_events_add_detail "${details_name}" "log_lines_scanned" "Log Lines Scanned" "${lines_scanned}"
            mst_fs_atomic_write "${cursor_path}" 0660 "${file_inode}|${file_size}"
        fi
    fi

    record_ref[duration_ms]="$(( $(mst_mrrf_now_epoch_ms) - started_ms ))"
    record_ref[observed_at]="$(mst_mrrf_now_utc)"
}
