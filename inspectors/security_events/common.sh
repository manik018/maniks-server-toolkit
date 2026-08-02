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
    export MST_SECURITY_EVENTS_FAIL2BAN_ENABLED="${MST_SECURITY_EVENTS_FAIL2BAN_ENABLED:-true}"
    export MST_SECURITY_EVENTS_FAIL2BAN_JAILS="${MST_SECURITY_EVENTS_FAIL2BAN_JAILS:-sshd}"
    export MST_SECURITY_EVENTS_FAIL2BAN_NEW_BLOCK_WARN_COUNT="${MST_SECURITY_EVENTS_FAIL2BAN_NEW_BLOCK_WARN_COUNT:-10}"
    export MST_SECURITY_EVENTS_SUDO_CHECK_ENABLED="${MST_SECURITY_EVENTS_SUDO_CHECK_ENABLED:-true}"
    export MST_SECURITY_EVENTS_CRON_CHECK_ENABLED="${MST_SECURITY_EVENTS_CRON_CHECK_ENABLED:-true}"
    export MST_SECURITY_EVENTS_PACKAGE_UPDATES_WARN_COUNT="${MST_SECURITY_EVENTS_PACKAGE_UPDATES_WARN_COUNT:-20}"
}

mst_security_events_snapshot_path() {
    local name="${1:?snapshot name required}" dir
    dir="$(mst_fs_validate_runtime_directory "${MST_STATE_DIR:?state dir required}/security_events")" || return 1
    mst_fs_ensure_directory "${dir}" || return 1
    mst_fs_validate_runtime_file_path "${dir}/${name}"
}

mst_security_events_add_typed_detail() {
    local details_name="${1:?details required}" key_name="${2:?key required}" label="${3:?label required}" value_type="${4:?type required}" value="${5:-}"
    local -n details_ref="${details_name}"
    details_ref+=("$(mst_mrrf_pack_detail "${key_name}" "${label}" "${value_type}" "${value}" "" "false")")
}

mst_security_events_append_extra_record() {
    local record_var="${1:?record var required}" records_name="${2:?records required}" statuses_name="${3:?statuses required}" severities_name="${4:?severities required}" vars_name="${5:?vars required}" record_status="${6:?status required}" record_severity="${7:?severity required}"
    local -n records_ref="${records_name}" statuses_ref="${statuses_name}" severities_ref="${severities_name}" vars_ref="${vars_name}" record_ref="${record_var}"
    records_ref+=("$(mst_mrrf_record_json "${record_var}" "${record_var}_DETAILS" "${record_var}_ERRORS")")
    statuses_ref+=("${record_status}"); severities_ref+=("${record_severity}"); vars_ref+=("${record_var}")
}

mst_security_events_new_user_summary() {
    local list="${1:-}" count=0 name shown=""
    for name in ${list}; do
        count=$((count + 1)); if (( count <= 5 )); then shown+="${shown:+, }${name}"; fi
    done
    if (( count > 5 )); then shown+=" +$((count - 5)) more"; fi
    printf '%s|%s' "${count}" "${shown}"
}

mst_security_events_collect_sudo_record() {
    local records_name="${1:?records required}" statuses_name="${2:?statuses required}" severities_name="${3:?severities required}" vars_name="${4:?vars required}"
    local group_line members snapshot current_list new_list removed_list snapshot_path baseline=false summary status result count shown name
    local -n records_ref="${records_name}" statuses_ref="${statuses_name}" severities_ref="${severities_name}" vars_ref="${vars_name}"
    [[ "${MST_SECURITY_EVENTS_SUDO_CHECK_ENABLED}" == "true" ]] || return 0
    group_line="$(getent group sudo 2>/dev/null || true)"
    members="${group_line##*:}"
    current_list="$(tr ',' '\n' <<< "${members}" | sed '/^$/d' | sort -u)"
    snapshot_path="$(mst_security_events_snapshot_path sudo_members.snapshot 2>/dev/null || true)"
    if [[ -n "${snapshot_path}" && -f "${snapshot_path}" ]]; then
        new_list="$(comm -23 <(printf '%s\n' "${current_list}") <(sort -u "${snapshot_path}"))"
        removed_list="$(comm -13 <(printf '%s\n' "${current_list}") <(sort -u "${snapshot_path}"))"
    else
        baseline=true; new_list=""; removed_list=""
    fi
    result="$(mst_security_events_new_user_summary "${new_list}")"; IFS='|' read -r count shown <<< "${result}"
    status=ok; (( count > 0 )) && status=warn
    if (( count > 0 )); then summary="${count} new sudo user(s) detected: ${shown}."; else summary="No sudo group membership changes."; fi
    declare -gA MST_SECURITY_EVENTS_SUDO_RECORD=(); declare -ga MST_SECURITY_EVENTS_SUDO_RECORD_DETAILS=() MST_SECURITY_EVENTS_SUDO_RECORD_ERRORS=()
    local -n record_ref=MST_SECURITY_EVENTS_SUDO_RECORD details_ref=MST_SECURITY_EVENTS_SUDO_RECORD_DETAILS errors_ref=MST_SECURITY_EVENTS_SUDO_RECORD_ERRORS
    record_ref=([result_id]="res_security_events.sudo_group_membership" [module]="security_events" [check]="sudo_group_membership" [target]="sudo" [status]="${status}" [severity]="${status}" [score]="null" [summary]="${summary}" [source_list]="getent,state" [provenance]="Current sudo group membership compared with an atomic snapshot." [privilege_requirement]="none" [redactions_present]="false" [duration_ms]="0" [observed_at]="$(mst_mrrf_now_utc)")
    mst_security_events_add_typed_detail MST_SECURITY_EVENTS_SUDO_RECORD_DETAILS current_sudo_user_count "Current Sudo Users" integer "$(printf '%s\n' "${current_list}" | sed '/^$/d' | wc -l | tr -d ' ')"
    mst_security_events_add_typed_detail MST_SECURITY_EVENTS_SUDO_RECORD_DETAILS new_sudo_user_count "New Sudo Users" integer "${count}"
    mst_security_events_add_typed_detail MST_SECURITY_EVENTS_SUDO_RECORD_DETAILS removed_sudo_user_count "Removed Sudo Users" integer "$(printf '%s\n' "${removed_list}" | sed '/^$/d' | wc -l | tr -d ' ')"
    [[ "${baseline}" == true ]] && mst_security_events_add_typed_detail MST_SECURITY_EVENTS_SUDO_RECORD_DETAILS baseline_established "Baseline Established" boolean true
    [[ -n "${snapshot_path}" ]] && mst_fs_atomic_write "${snapshot_path}" 0660 "${current_list}"
    mst_security_events_append_extra_record MST_SECURITY_EVENTS_SUDO_RECORD "${records_name}" "${statuses_name}" "${severities_name}" "${vars_name}" "${status}" "${status}"
}

mst_security_events_collect_cron_record() {
    local records_name="${1:?records required}" statuses_name="${2:?statuses required}" severities_name="${3:?severities required}" vars_name="${4:?vars required}" current snapshot_path previous changed=false
    local -n records_ref="${records_name}" statuses_ref="${statuses_name}" severities_ref="${severities_name}" vars_ref="${vars_name}"
    [[ "${MST_SECURITY_EVENTS_CRON_CHECK_ENABLED}" == "true" ]] || return 0
    current="$( (crontab -l -u root 2>/dev/null || true); for file in /etc/cron.d/*; do [[ -f "${file}" ]] || continue; sed '/^[[:space:]]*#/d; /^[[:space:]]*$/d' "${file}"; done )"
    snapshot_path="$(mst_security_events_snapshot_path cron_snapshot.state 2>/dev/null || true)"
    [[ -f "${snapshot_path}" ]] && [[ "${current}" != "$(< "${snapshot_path}")" ]] && changed=true
    declare -gA MST_SECURITY_EVENTS_CRON_RECORD=(); declare -ga MST_SECURITY_EVENTS_CRON_RECORD_DETAILS=() MST_SECURITY_EVENTS_CRON_RECORD_ERRORS=()
    local -n record_ref=MST_SECURITY_EVENTS_CRON_RECORD
    status=ok; [[ "${changed}" == true ]] && status=warn
    if [[ "${changed}" == true ]]; then summary="Cron job configuration changed since last check — review root crontab and /etc/cron.d/."; else summary="No cron job changes detected."; fi
    record_ref=([result_id]="res_security_events.cron_job_changes" [module]="security_events" [check]="cron_job_changes" [target]="system-cron" [status]="${status}" [severity]="${status}" [score]="null" [summary]="${summary}" [source_list]="crontab,filesystem,state" [provenance]="Normalized root crontab and /etc/cron.d entries compared with a snapshot." [privilege_requirement]="none" [redactions_present]="false" [duration_ms]="0" [observed_at]="$(mst_mrrf_now_utc)")
    mst_security_events_add_typed_detail MST_SECURITY_EVENTS_CRON_RECORD_DETAILS cron_changed "Cron Changed" boolean "${changed}"
    [[ -f "${snapshot_path}" ]] || mst_security_events_add_typed_detail MST_SECURITY_EVENTS_CRON_RECORD_DETAILS baseline_established "Baseline Established" boolean true
    [[ -n "${snapshot_path}" ]] && mst_fs_atomic_write "${snapshot_path}" 0660 "${current}"
    mst_security_events_append_extra_record MST_SECURITY_EVENTS_CRON_RECORD "${records_name}" "${statuses_name}" "${severities_name}" "${vars_name}" "${status}" "${status}"
}

mst_security_events_collect_package_record() {
    local records_name="${1:?records required}" statuses_name="${2:?statuses required}" severities_name="${3:?severities required}" vars_name="${4:?vars required}" output count status summary
    local -n records_ref="${records_name}" statuses_ref="${statuses_name}" severities_ref="${severities_name}" vars_ref="${vars_name}"
    declare -gA MST_SECURITY_EVENTS_PACKAGE_RECORD=(); declare -ga MST_SECURITY_EVENTS_PACKAGE_RECORD_DETAILS=() MST_SECURITY_EVENTS_PACKAGE_RECORD_ERRORS=()
    local -n record_ref=MST_SECURITY_EVENTS_PACKAGE_RECORD
    if ! mst_command_exists apt; then status=unavailable; summary="Package manager apt is unavailable."; count=0; else output="$(apt list --upgradable 2>/dev/null || true)"; count="$(grep -v '^Listing\.\.\.' <<< "${output}" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"; status=ok; (( count > 10#${MST_SECURITY_EVENTS_PACKAGE_UPDATES_WARN_COUNT} )) && status=warn; summary="${count} package update(s) available."; fi
    record_ref=([result_id]="res_security_events.package_updates" [module]="security_events" [check]="package_updates" [target]="apt" [status]="${status}" [severity]="${status}" [score]="null" [summary]="${summary}" [source_list]="apt" [provenance]="Current apt upgrade listing." [privilege_requirement]="none" [redactions_present]="false" [duration_ms]="0" [observed_at]="$(mst_mrrf_now_utc)")
    mst_security_events_add_typed_detail MST_SECURITY_EVENTS_PACKAGE_RECORD_DETAILS upgradable_package_count "Upgradable Packages" integer "${count}"
    [[ "${status}" == unavailable ]] && mst_security_events_add_error MST_SECURITY_EVENTS_PACKAGE_RECORD_ERRORS dependency APT_UNAVAILABLE "The apt command is unavailable."
    mst_security_events_append_extra_record MST_SECURITY_EVENTS_PACKAGE_RECORD "${records_name}" "${statuses_name}" "${severities_name}" "${vars_name}" "${status}" "${status}"
}

mst_security_events_fail2ban_state_path() {
    local jail="${1:?jail required}" dir
    dir="$(mst_fs_validate_runtime_directory "${MST_STATE_DIR:?state dir required}/security_events")" || return 1
    mst_fs_ensure_directory "${dir}" || return 1
    mst_fs_validate_runtime_file_path "${dir}/fail2ban_${jail}.banned"
}

mst_security_events_fail2ban_record() {
    local jail="${1:?jail required}" status="${2:?status required}" summary="${3:?summary required}"
    local details_name="${4:?details required}" errors_name="${5:?errors required}" record_name="${6:?record required}"
    local -n record_ref="${record_name}"
    record_ref=()
    record_ref[result_id]="res_security_events.fail2ban_${jail}"
    record_ref[module]="security_events"
    record_ref[check]="fail2ban_jail_status"
    record_ref[target]="${jail}"
    record_ref[status]="${status}"
    record_ref[severity]="${status}"
    record_ref[score]="null"
    record_ref[summary]="${summary}"
    record_ref[source_list]="fail2ban-client,state"
    record_ref[provenance]="Fail2Ban jail status and incremental banned-IP state."
    record_ref[privilege_requirement]="none"
    record_ref[redactions_present]="false"
    record_ref[duration_ms]="0"
    record_ref[observed_at]="$(mst_mrrf_now_utc)"
}

mst_security_events_collect_fail2ban_records() {
    local records_name="${1:?records required}" statuses_name="${2:?statuses required}" severities_name="${3:?severities required}" vars_name="${4:?vars required}"
    local -n records_ref="${records_name}" statuses_ref="${statuses_name}" severities_ref="${severities_name}" vars_ref="${vars_name}"
    local jail output current total list state_path current_list new_count baseline status summary record_var details_var errors_var ip
    records_ref=(); statuses_ref=(); severities_ref=(); vars_ref=()
    [[ "${MST_SECURITY_EVENTS_FAIL2BAN_ENABLED}" == "true" ]] || return 0
    if ! mst_command_exists fail2ban-client; then
        declare -gA MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_RECORD=()
        declare -ga MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_DETAILS=() MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_ERRORS=()
        mst_security_events_fail2ban_record "fail2ban" unavailable "Fail2Ban is not installed or not reachable." MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_DETAILS MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_ERRORS MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_RECORD
        mst_security_events_add_error MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_ERRORS dependency FAIL2BAN_UNAVAILABLE "Fail2Ban is not installed or not reachable."
        records_ref+=("$(mst_mrrf_record_json MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_RECORD MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_DETAILS MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_ERRORS)")
        statuses_ref+=(unavailable); severities_ref+=(unknown); vars_ref+=(MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_RECORD)
        return 0
    fi
    if ! mst_exec_capture_stdout "${MST_SECURITY_EVENTS_TIMEOUT_SECONDS}" fail2ban-client status >/dev/null 2>&1; then
        declare -gA MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_RECORD=()
        declare -ga MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_DETAILS=() MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_ERRORS=()
        mst_security_events_fail2ban_record "fail2ban" unavailable "Fail2Ban is not installed or not reachable." MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_DETAILS MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_ERRORS MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_RECORD
        mst_security_events_add_error MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_ERRORS dependency FAIL2BAN_UNAVAILABLE "Fail2Ban is not installed or not reachable."
        records_ref+=("$(mst_mrrf_record_json MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_RECORD MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_DETAILS MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_ERRORS)")
        statuses_ref+=(unavailable); severities_ref+=(unknown); vars_ref+=(MST_SECURITY_EVENTS_FAIL2BAN_UNAVAILABLE_RECORD)
        return 0
    fi
    IFS=';' read -r -a jails <<< "${MST_SECURITY_EVENTS_FAIL2BAN_JAILS}"
    for jail in "${jails[@]}"; do
        [[ -n "${jail}" ]] || continue
        record_var="MST_SECURITY_EVENTS_FAIL2BAN_${jail}_RECORD"; details_var="MST_SECURITY_EVENTS_FAIL2BAN_${jail}_DETAILS"; errors_var="MST_SECURITY_EVENTS_FAIL2BAN_${jail}_ERRORS"
        declare -gA "${record_var}"; declare -ga "${details_var}" "${errors_var}"
        local -n record_ref="${record_var}" details_ref="${details_var}" errors_ref="${errors_var}"
        details_ref=(); errors_ref=()
        if ! output="$(mst_exec_capture_stdout "${MST_SECURITY_EVENTS_TIMEOUT_SECONDS}" fail2ban-client status "${jail}" 2>&1)"; then
            mst_security_events_fail2ban_record "${jail}" unavailable "Fail2Ban jail '${jail}' is not configured." "${details_var}" "${errors_var}" "${record_var}"
            mst_security_events_add_error "${errors_var}" dependency FAIL2BAN_JAIL_MISSING "Fail2Ban jail '${jail}' is not configured."
            records_ref+=("$(mst_mrrf_record_json "${record_var}" "${details_var}" "${errors_var}")"); statuses_ref+=(unavailable); severities_ref+=(unknown); vars_ref+=("${record_var}"); continue
        fi
        current="$(sed -n 's/^[^A-Za-z]*Currently banned:[[:space:]]*\([0-9][0-9]*\).*/\1/p' <<< "${output}" | head -n1)"
        total="$(sed -n 's/^[^A-Za-z]*Total banned:[[:space:]]*\([0-9][0-9]*\).*/\1/p' <<< "${output}" | head -n1)"
        list="$(sed -n 's/^[^A-Za-z]*Banned IP list:[[:space:]]*//p' <<< "${output}" | head -n1)"
        current_list="$(tr ' ' '\n' <<< "${list}" | sed '/^$/d')"
        [[ "${current}" =~ ^[0-9]+$ && "${total}" =~ ^[0-9]+$ ]] || { mst_security_events_fail2ban_record "${jail}" unavailable "Fail2Ban jail '${jail}' is not configured." "${details_var}" "${errors_var}" "${record_var}"; records_ref+=("$(mst_mrrf_record_json "${record_var}" "${details_var}" "${errors_var}")"); statuses_ref+=(unavailable); severities_ref+=(unknown); vars_ref+=("${record_var}"); continue; }
        state_path="$(mst_security_events_fail2ban_state_path "${jail}" 2>/dev/null || true)"; baseline=false; new_count=0
        if [[ -n "${state_path}" && -f "${state_path}" ]]; then
            for ip in ${list}; do grep -F -x -q -- "${ip}" "${state_path}" || new_count=$((new_count + 1)); done
        else
            baseline=true
        fi
        [[ "${baseline}" == true ]] && new_count=0
        status=ok; (( new_count > 10#${MST_SECURITY_EVENTS_FAIL2BAN_NEW_BLOCK_WARN_COUNT} )) && status=warn
        summary="${jail} jail: ${current} currently banned, ${total} total banned, ${new_count} new blocks since last check."
        mst_security_events_fail2ban_record "${jail}" "${status}" "${summary}" "${details_var}" "${errors_var}" "${record_var}"
        mst_security_events_add_detail "${details_var}" currently_banned "Currently Banned" "${current}"; mst_security_events_add_detail "${details_var}" total_banned "Total Banned" "${total}"; mst_security_events_add_detail "${details_var}" new_blocked_ip_count "New Blocked IPs" "${new_count}"
        [[ "${baseline}" == true ]] && mst_security_events_add_detail "${details_var}" baseline_established "Baseline Established" 1
        [[ -n "${state_path}" ]] && mst_fs_atomic_write "${state_path}" 0660 "${current_list}"
        records_ref+=("$(mst_mrrf_record_json "${record_var}" "${details_var}" "${errors_var}")"); statuses_ref+=("${status}"); severities_ref+=("${status}"); vars_ref+=("${record_var}")
    done
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
