#!/usr/bin/env bash
# Validate security collectors against configuration and service fixtures.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/security-collectors"
PROC_DIR="${TMP_DIR}/proc"
SSH_DIR="${TMP_DIR}/ssh"
UFW_DIR="${TMP_DIR}/ufw"
APT_DIR="${TMP_DIR}/apt/apt.conf.d"

mkdir -p "${PROC_DIR}/sys/kernel" "${SSH_DIR}/sshd_config.d" "${UFW_DIR}" "${APT_DIR}"

cat > "${PROC_DIR}/sys/kernel/hostname" <<'EOF'
security-test
EOF

cat > "${SSH_DIR}/sshd_config" <<'EOF'
PermitRootLogin yes
Include sshd_config.d/*.conf
PasswordAuthentication yes
EOF

cat > "${SSH_DIR}/sshd_config.d/50-hardening.conf" <<'EOF'
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
EOF

cat > "${UFW_DIR}/ufw.conf" <<'EOF'
ENABLED=yes
EOF

cat > "${TMP_DIR}/ufw-defaults" <<'EOF'
DEFAULT_INPUT_POLICY="DROP"
DEFAULT_OUTPUT_POLICY="ACCEPT"
EOF

cat > "${APT_DIR}/20auto-upgrades" <<'EOF'
APT::Periodic::Unattended-Upgrade "1";
EOF

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/inspectors/security.sh"

export MST_SECURITY_PROC_DIR="${PROC_DIR}"
export MST_SECURITY_SSH_CONFIG_FILE="${SSH_DIR}/sshd_config"
export MST_SECURITY_UFW_CONF_FILE="${UFW_DIR}/ufw.conf"
export MST_SECURITY_UFW_DEFAULTS_FILE="${TMP_DIR}/ufw-defaults"
export MST_SECURITY_AUTO_UPGRADES_FILE="${APT_DIR}/20auto-upgrades"
export MST_SECURITY_SSH_SERVICE_CANDIDATES="ssh.service"
export MST_SECURITY_FAIL2BAN_SERVICE_CANDIDATES="fail2ban.service"
export MST_SECURITY_TIMESYNC_SERVICE_CANDIDATES="systemd-timesyncd.service"

mst_security_systemctl_show() {
    case "${1}" in
        ssh.service)
            cat <<'EOF'
Id=ssh.service
LoadState=loaded
ActiveState=active
UnitFileState=enabled
Result=success
EOF
            ;;
        fail2ban.service)
            cat <<'EOF'
Id=fail2ban.service
LoadState=loaded
ActiveState=active
UnitFileState=enabled
Result=success
EOF
            ;;
        systemd-timesyncd.service)
            cat <<'EOF'
Id=systemd-timesyncd.service
LoadState=loaded
ActiveState=active
UnitFileState=enabled
Result=success
EOF
            ;;
        missing.service)
            cat <<'EOF'
Id=missing.service
LoadState=not-found
ActiveState=inactive
UnitFileState=disabled
Result=success
EOF
            ;;
        *)
            return 1
            ;;
    esac
}

mst_security_systemctl_is_active() {
    case "${1}" in
        ssh.service|fail2ban.service|systemd-timesyncd.service) printf 'active' ;;
        *) printf 'inactive' ;;
    esac
}

mst_security_systemctl_is_enabled() {
    case "${1}" in
        ssh.service|fail2ban.service|systemd-timesyncd.service) printf 'enabled' ;;
        *) printf 'disabled' ;;
    esac
}

mst_security_timedatectl_show() {
    cat <<'EOF'
NTPSynchronized=yes
SystemClockSynchronized=yes
CanNTP=yes
NTP=yes
EOF
}

mst_security_fail2ban_status_output() {
    cat <<'EOF'
Status
|- Number of jail: 2
`- Jail list: sshd, nginx-http-auth
EOF
}

mst_command_exists() {
    case "${1}" in
        ufw|fail2ban-client|timedatectl|unattended-upgrade) return 0 ;;
        *) command -v "${1}" >/dev/null 2>&1 ;;
    esac
}

declare -A ssh_record=()
declare -a ssh_details=() ssh_errors=() ssh_rows=()
mst_security_collect_ssh ssh ssh_record ssh_details ssh_errors ssh_rows
[[ "${ssh_record[status]}" == "ok" ]] || exit 1
[[ "${ssh_record[summary]}" == *"PermitRootLogin=no"* ]] || exit 1

mv "${SSH_DIR}/sshd_config" "${SSH_DIR}/sshd_config.missing"
declare -A ssh_missing_record=()
declare -a ssh_missing_details=() ssh_missing_errors=() ssh_missing_rows=()
mst_security_collect_ssh ssh ssh_missing_record ssh_missing_details ssh_missing_errors ssh_missing_rows
[[ "${ssh_missing_record[status]}" == "unknown" ]] || exit 1
mv "${SSH_DIR}/sshd_config.missing" "${SSH_DIR}/sshd_config"

declare -A ufw_record=()
declare -a ufw_details=() ufw_errors=() ufw_rows=()
mst_security_collect_ufw ufw ufw_record ufw_details ufw_errors ufw_rows
[[ "${ufw_record[status]}" == "ok" ]] || exit 1

mv "${UFW_DIR}/ufw.conf" "${UFW_DIR}/ufw.conf.missing"
mv "${TMP_DIR}/ufw-defaults" "${TMP_DIR}/ufw-defaults.missing"
mst_command_exists() {
    case "${1}" in
        fail2ban-client|timedatectl|unattended-upgrade) return 0 ;;
        ufw) return 1 ;;
        *) command -v "${1}" >/dev/null 2>&1 ;;
    esac
}
declare -A ufw_missing_record=()
declare -a ufw_missing_details=() ufw_missing_errors=() ufw_missing_rows=()
mst_security_collect_ufw ufw ufw_missing_record ufw_missing_details ufw_missing_errors ufw_missing_rows
[[ "${ufw_missing_record[status]}" == "unavailable" ]] || exit 1
mv "${UFW_DIR}/ufw.conf.missing" "${UFW_DIR}/ufw.conf"
mv "${TMP_DIR}/ufw-defaults.missing" "${TMP_DIR}/ufw-defaults"

mst_command_exists() {
    case "${1}" in
        ufw|fail2ban-client|timedatectl|unattended-upgrade) return 0 ;;
        *) command -v "${1}" >/dev/null 2>&1 ;;
    esac
}

declare -A fail2ban_record=()
declare -a fail2ban_details=() fail2ban_errors=() fail2ban_rows=()
mst_security_collect_fail2ban fail2ban fail2ban_record fail2ban_details fail2ban_errors fail2ban_rows
[[ "${fail2ban_record[status]}" == "ok" ]] || exit 1
[[ "${fail2ban_record[summary]}" == *"2 active jails"* ]] || exit 1

export MST_SECURITY_FAIL2BAN_SERVICE_CANDIDATES="missing.service"
declare -A fail2ban_missing_record=()
declare -a fail2ban_missing_details=() fail2ban_missing_errors=() fail2ban_missing_rows=()
mst_security_collect_fail2ban fail2ban fail2ban_missing_record fail2ban_missing_details fail2ban_missing_errors fail2ban_missing_rows
[[ "${fail2ban_missing_record[status]}" == "unavailable" ]] || exit 1
export MST_SECURITY_FAIL2BAN_SERVICE_CANDIDATES="fail2ban.service"

declare -A upgrades_record=()
declare -a upgrades_details=() upgrades_errors=() upgrades_rows=()
mst_security_collect_unattended_upgrades unattended_upgrades upgrades_record upgrades_details upgrades_errors upgrades_rows
[[ "${upgrades_record[status]}" == "ok" ]] || exit 1

mv "${APT_DIR}/20auto-upgrades" "${APT_DIR}/20auto-upgrades.missing"
mst_command_exists() {
    case "${1}" in
        ufw|fail2ban-client|timedatectl) return 0 ;;
        unattended-upgrade) return 1 ;;
        *) command -v "${1}" >/dev/null 2>&1 ;;
    esac
}
declare -A upgrades_missing_record=()
declare -a upgrades_missing_details=() upgrades_missing_errors=() upgrades_missing_rows=()
mst_security_collect_unattended_upgrades unattended_upgrades upgrades_missing_record upgrades_missing_details upgrades_missing_errors upgrades_missing_rows
[[ "${upgrades_missing_record[status]}" == "unavailable" ]] || exit 1
mv "${APT_DIR}/20auto-upgrades.missing" "${APT_DIR}/20auto-upgrades"

mst_command_exists() {
    case "${1}" in
        ufw|fail2ban-client|timedatectl|unattended-upgrade) return 0 ;;
        *) command -v "${1}" >/dev/null 2>&1 ;;
    esac
}

declare -A time_record=()
declare -a time_details=() time_errors=() time_rows=()
mst_security_collect_time_sync time_sync time_record time_details time_errors time_rows
[[ "${time_record[status]}" == "ok" ]] || exit 1

mst_security_timedatectl_show() {
    cat <<'EOF'
NTPSynchronized=no
SystemClockSynchronized=no
CanNTP=yes
NTP=no
EOF
}
declare -A time_inactive_record=()
declare -a time_inactive_details=() time_inactive_errors=() time_inactive_rows=()
mst_security_collect_time_sync time_sync time_inactive_record time_inactive_details time_inactive_errors time_inactive_rows
[[ "${time_inactive_record[status]}" == "warn" ]] || exit 1

printf 'test_security_collectors.sh passed.\n'
