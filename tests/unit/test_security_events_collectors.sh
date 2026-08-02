#!/usr/bin/env bash
# Validate incremental SSH login activity collection.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/security-events-collectors"
STATE_DIR="${TMP_DIR}/state"
LOG_PATH="${TMP_DIR}/auth.log"
rm -rf -- "${TMP_DIR}"
mkdir -p -- "${STATE_DIR}"
trap 'rm -rf -- "${TMP_DIR}"' EXIT INT TERM

source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/inspectors/security_events.sh"

export MST_STATE_DIR="${STATE_DIR}"
export MST_SECURITY_EVENTS_AUTH_LOG_PATH="${LOG_PATH}"
export MST_SECURITY_EVENTS_SSH_FAILED_WARN_COUNT="10"
export MST_SECURITY_EVENTS_SSH_ROOT_ATTEMPT_WARN_COUNT="1"

mst_fs_validate_runtime_directory() {
    local path="${1:?path required}"
    [[ "${path}" == "${STATE_DIR}" || "${path}" == "${STATE_DIR}"/* ]] || return 1
    [[ ! -L "${path}" ]] || return 1
    printf '%s' "${path}"
}

mst_fs_validate_runtime_file_path() {
    local path="${1:?path required}"
    [[ "${path}" == "${STATE_DIR}"/* ]] || return 1
    [[ ! -L "${path}" ]] || return 1
    printf '%s' "${path}"
}

collect() {
    declare -gA test_record=()
    declare -ga test_details=() test_errors=()
    mst_security_events_collect test_record test_details test_errors
}

cat > "${LOG_PATH}" <<'EOF'
Aug 02 10:00:00 host sshd[1]: Failed password for invalid user guest from 10.0.0.1 port 22 ssh2
Aug 02 10:00:01 host sshd[2]: Accepted publickey for alice from 10.0.0.2 port 22 ssh2
Aug 02 10:00:02 host sshd[3]: Failed password for root from 10.0.0.3 port 22 ssh2
EOF

collect
[[ "${test_record[check]}" == "ssh_login_activity" ]] || exit 1
[[ "${test_record[status]}" == "warn" ]] || exit 1
[[ "${test_record[summary]}" == "2 failed SSH login(s), 1 accepted, 1 root login attempts since last check." ]] || exit 1
[[ "$(< "${STATE_DIR}/security_events/auth_log.cursor")" == "$(stat -c '%i' -- "${LOG_PATH}")|$(stat -c '%s' -- "${LOG_PATH}")" ]] || exit 1
printf '%s\n' "${test_details[@]}" | grep -F $'ssh_failed_count\037Failed SSH Logins\037integer\0372' >/dev/null || exit 1
printf '%s\n' "${test_details[@]}" | grep -F $'log_lines_scanned\037Log Lines Scanned\037integer\0373' >/dev/null || exit 1

printf '%s\n' 'Aug 02 10:00:03 host sshd[4]: Accepted password for bob from 10.0.0.4 port 22 ssh2' >> "${LOG_PATH}"
collect
[[ "${test_record[status]}" == "ok" ]] || exit 1
[[ "${test_record[summary]}" == "0 failed SSH login(s), 1 accepted, 0 root login attempts since last check." ]] || exit 1

printf '%s\n' "1|0" > "${STATE_DIR}/security_events/auth_log.cursor"
collect
[[ "${test_record[summary]}" == "2 failed SSH login(s), 2 accepted, 1 root login attempts since last check." ]] || exit 1

export MST_SECURITY_EVENTS_FAIL2BAN_ENABLED="true"
export MST_SECURITY_EVENTS_FAIL2BAN_JAILS="sshd"
export MST_SECURITY_EVENTS_FAIL2BAN_NEW_BLOCK_WARN_COUNT="1"
FAIL2BAN_BANNED="1.2.3.4 5.6.7.8 9.9.9.9"
mst_command_exists() { [[ "${1}" == "fail2ban-client" ]]; }
mst_exec_capture_stdout() {
    if [[ "${*: -1}" == "status" ]]; then
        printf 'Status\n'; return 0
    fi
    if [[ "${*: -1}" == "sshd" ]]; then
        printf '%s\n' 'Status for the jail: sshd' '|- Filter' '|  |- Currently failed:'$'\t''2' '|  `- Total failed:'$'\t''57' '`- Actions' '   |- Currently banned:'$'\t''3' '   |- Total banned:'$'\t''12'
        printf '   `- Banned IP list:'$'\t''%s\n' "${FAIL2BAN_BANNED}"
        return 0
    fi
    return 1
}
declare -a f2b_jsons=() f2b_statuses=() f2b_severities=() f2b_vars=()
mst_security_events_collect_fail2ban_records f2b_jsons f2b_statuses f2b_severities f2b_vars
[[ "${f2b_statuses[0]}" == "ok" ]] || exit 1
grep -F 'new_blocked_ip_count' <<< "${f2b_jsons[0]}" >/dev/null || exit 1
grep -F '"value":0' <<< "${f2b_jsons[0]}" >/dev/null || exit 1
[[ "$(< "${STATE_DIR}/security_events/fail2ban_sshd.banned")" == $'1.2.3.4\n5.6.7.8\n9.9.9.9' ]] || exit 1
FAIL2BAN_BANNED="5.6.7.8 10.10.10.10 1.2.3.4"
mst_security_events_collect_fail2ban_records f2b_jsons f2b_statuses f2b_severities f2b_vars
[[ "${f2b_statuses[0]}" == "ok" ]] || exit 1
grep -F '"value":1' <<< "${f2b_jsons[0]}" >/dev/null || exit 1
FAIL2BAN_BANNED="5.6.7.8 10.10.10.10 11.11.11.11 12.12.12.12"
mst_security_events_collect_fail2ban_records f2b_jsons f2b_statuses f2b_severities f2b_vars
[[ "${f2b_statuses[0]}" == "warn" ]] || exit 1
export MST_SECURITY_EVENTS_FAIL2BAN_JAILS="sshd;missing"
mst_security_events_collect_fail2ban_records f2b_jsons f2b_statuses f2b_severities f2b_vars
[[ "${#f2b_statuses[@]}" -eq 2 ]] || exit 1
[[ "${f2b_statuses[1]}" == "unavailable" ]] || exit 1

export MST_SECURITY_EVENTS_SUDO_CHECK_ENABLED="true"
SUDO_MEMBERS="alice,bob"
getent() { [[ "${1}" == "group" && "${2}" == "sudo" ]] && printf 'sudo:x:27:%s\n' "${SUDO_MEMBERS}"; }
declare -a extra_jsons=() extra_statuses=() extra_severities=() extra_vars=()
mst_security_events_collect_sudo_record extra_jsons extra_statuses extra_severities extra_vars
grep -F '"value":0' <<< "${extra_jsons[0]}" >/dev/null || exit 1
SUDO_MEMBERS="alice,bob,charlie"
extra_jsons=(); extra_statuses=(); extra_severities=(); extra_vars=()
mst_security_events_collect_sudo_record extra_jsons extra_statuses extra_severities extra_vars
[[ "${extra_statuses[0]}" == "warn" ]] || exit 1
grep -F 'charlie' <<< "${extra_jsons[0]}" >/dev/null || exit 1
SUDO_MEMBERS="alice,bob"
extra_jsons=(); extra_statuses=(); extra_severities=(); extra_vars=()
mst_security_events_collect_sudo_record extra_jsons extra_statuses extra_severities extra_vars
[[ "${extra_statuses[0]}" == "ok" ]] || exit 1
grep -F 'removed_sudo_user_count' <<< "${extra_jsons[0]}" >/dev/null || exit 1

export MST_SECURITY_EVENTS_CRON_CHECK_ENABLED="true"
CRON_CONTENT=""
crontab() { [[ "${1}" == "-l" ]] && { [[ -n "${CRON_CONTENT}" ]] && printf '%s\n' "${CRON_CONTENT}" || return 1; }; }
mst_security_events_collect_cron_record extra_jsons extra_statuses extra_severities extra_vars
[[ "${extra_statuses[0]}" == "ok" ]] || exit 1
extra_jsons=(); extra_statuses=(); extra_severities=(); extra_vars=()
mst_security_events_collect_cron_record extra_jsons extra_statuses extra_severities extra_vars
[[ "${extra_statuses[0]}" == "ok" ]] || exit 1
CRON_CONTENT='0 * * * * root /usr/bin/true'
extra_jsons=(); extra_statuses=(); extra_severities=(); extra_vars=()
mst_security_events_collect_cron_record extra_jsons extra_statuses extra_severities extra_vars
[[ "${extra_statuses[0]}" == "warn" ]] || exit 1
MST_SECURITY_EVENTS_CRON_CHECK_ENABLED="false"

MST_SECURITY_EVENTS_PACKAGE_UPDATES_WARN_COUNT="1"
mst_command_exists() { [[ "${1}" == "apt" ]]; }
apt() { printf '%s\n' 'Listing...' 'pkg1/stable 1.0 amd64 [upgradable from: 0.9]' 'pkg2/stable 2.0 amd64 [upgradable from: 1.9]'; }
mst_security_events_collect_package_record extra_jsons extra_statuses extra_severities extra_vars
[[ "${extra_statuses[0]}" == "warn" ]] || exit 1
unset -f apt mst_command_exists getent crontab

unset -f mst_command_exists mst_exec_capture_stdout
export MST_SECURITY_EVENTS_FAIL2BAN_ENABLED="false"

rm -f -- "${LOG_PATH}"
collect
[[ "${test_record[status]}" == "unavailable" ]] || exit 1
[[ "${#test_errors[@]}" -eq 1 ]] || exit 1

printf 'test_security_events_collectors.sh passed.\n'
