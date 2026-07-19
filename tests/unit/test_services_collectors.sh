#!/usr/bin/env bash
# Validate services collectors against active, inactive, failed, unavailable, and permission scenarios.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/services-collectors"
PROC_DIR="${TMP_DIR}/proc"

mkdir -p "${PROC_DIR}/sys/kernel"

cat > "${PROC_DIR}/uptime" <<'EOF'
7200.00 1000.00
EOF

cat > "${PROC_DIR}/sys/kernel/hostname" <<'EOF'
services-test
EOF

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/inspectors/services.sh"

export MST_SERVICES_PROC_DIR="${PROC_DIR}"

mst_services_systemctl_show() {
    case "${1}" in
        nginx.service)
            cat <<'EOF'
Id=nginx.service
LoadState=loaded
ActiveState=active
SubState=running
UnitFileState=enabled
MainPID=1200
MemoryCurrent=134217728
NRestarts=1
ActiveEnterTimestampMonotonic=3600000000
Result=success
EOF
            ;;
        cron.service)
            cat <<'EOF'
Id=cron.service
LoadState=loaded
ActiveState=inactive
SubState=dead
UnitFileState=enabled
MainPID=0
MemoryCurrent=0
NRestarts=0
ActiveEnterTimestampMonotonic=0
Result=success
EOF
            ;;
        mariadb.service)
            cat <<'EOF'
Id=mariadb.service
LoadState=loaded
ActiveState=failed
SubState=failed
UnitFileState=enabled
MainPID=4500
MemoryCurrent=268435456
NRestarts=3
ActiveEnterTimestampMonotonic=1800000000
Result=failed
EOF
            ;;
        fail2ban.service)
            cat <<'EOF'
Access denied
EOF
            return 1
            ;;
        missing.service)
            cat <<'EOF'
Id=missing.service
LoadState=not-found
ActiveState=inactive
SubState=dead
UnitFileState=disabled
MainPID=0
MemoryCurrent=0
NRestarts=0
ActiveEnterTimestampMonotonic=0
Result=success
EOF
            ;;
        *)
            return 1
            ;;
    esac
}

mst_services_systemctl_is_active() {
    case "${1}" in
        nginx.service) printf 'active' ;;
        cron.service) printf 'inactive' ;;
        mariadb.service) printf 'failed' ;;
        *) printf 'unknown' ;;
    esac
}

mst_services_systemctl_is_enabled() {
    case "${1}" in
        nginx.service|cron.service|mariadb.service) printf 'enabled' ;;
        *) printf 'unknown' ;;
    esac
}

export MST_SERVICES_NGINX_CANDIDATES="nginx.service"
export MST_SERVICES_CRON_CANDIDATES="cron.service"
export MST_SERVICES_DATABASE_CANDIDATES="mariadb.service"
export MST_SERVICES_FAIL2BAN_CANDIDATES="fail2ban.service"
export MST_SERVICES_SSH_CANDIDATES="missing.service"

declare -A active_record=()
declare -a active_details=() active_errors=() active_rows=()
mst_services_collect_service nginx active_record active_details active_errors active_rows
[[ "${active_record[status]}" == "ok" ]] || exit 1
[[ "${active_record[target]}" == "nginx.service" ]] || exit 1
[[ "${active_rows[0]}" == Unit* ]] || exit 1
[[ "${active_details[6]}" == uptime_seconds* ]] || exit 1

declare -A inactive_record=()
declare -a inactive_details=() inactive_errors=() inactive_rows=()
mst_services_collect_service cron inactive_record inactive_details inactive_errors inactive_rows
[[ "${inactive_record[status]}" == "warn" ]] || exit 1
[[ "${inactive_record[summary]}" == *"inactive"* ]] || exit 1

declare -A failed_record=()
declare -a failed_details=() failed_errors=() failed_rows=()
mst_services_collect_service database failed_record failed_details failed_errors failed_rows
[[ "${failed_record[status]}" == "critical" ]] || exit 1
[[ "${failed_record[severity]}" == "critical" ]] || exit 1

declare -A permission_record=()
declare -a permission_details=() permission_errors=() permission_rows=()
mst_services_collect_service fail2ban permission_record permission_details permission_errors permission_rows
[[ "${permission_record[status]}" == "unavailable" ]] || exit 1
[[ "${permission_errors[0]}" == permission* ]] || exit 1

declare -A missing_record=()
declare -a missing_details=() missing_errors=() missing_rows=()
mst_services_collect_service ssh missing_record missing_details missing_errors missing_rows
[[ "${missing_record[status]}" == "unavailable" ]] || exit 1
[[ "${missing_errors[0]}" == dependency* ]] || exit 1

printf 'test_services_collectors.sh passed.\n'
