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

rm -f -- "${LOG_PATH}"
collect
[[ "${test_record[status]}" == "unavailable" ]] || exit 1
[[ "${#test_errors[@]}" -eq 1 ]] || exit 1

printf 'test_security_events_collectors.sh passed.\n'
