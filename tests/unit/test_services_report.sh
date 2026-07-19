#!/usr/bin/env bash
# Validate aggregate services MRRF1 generation and collector isolation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/services-report"
PROC_DIR="${TMP_DIR}/proc"

mkdir -p "${PROC_DIR}/sys/kernel"

cat > "${PROC_DIR}/uptime" <<'EOF'
7200.00 1000.00
EOF

cat > "${PROC_DIR}/sys/kernel/hostname" <<'EOF'
services-report
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
        php8.3-fpm.service)
            cat <<'EOF'
Id=php8.3-fpm.service
LoadState=loaded
ActiveState=active
SubState=running
UnitFileState=enabled
MainPID=2200
MemoryCurrent=67108864
NRestarts=0
ActiveEnterTimestampMonotonic=3600000000
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
NRestarts=2
ActiveEnterTimestampMonotonic=1800000000
Result=failed
EOF
            ;;
        redis-server.service)
            cat <<'EOF'
Id=redis-server.service
LoadState=loaded
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
        cron.service)
            cat <<'EOF'
Id=cron.service
LoadState=loaded
ActiveState=active
SubState=running
UnitFileState=enabled
MainPID=300
MemoryCurrent=33554432
NRestarts=0
ActiveEnterTimestampMonotonic=3000000000
Result=success
EOF
            ;;
        fail2ban.service)
            cat <<'EOF'
Id=fail2ban.service
LoadState=loaded
ActiveState=active
SubState=running
UnitFileState=enabled
MainPID=3300
MemoryCurrent=50331648
NRestarts=1
ActiveEnterTimestampMonotonic=4000000000
Result=success
EOF
            ;;
        ssh.service)
            cat <<'EOF'
Id=ssh.service
LoadState=loaded
ActiveState=active
SubState=running
UnitFileState=enabled
MainPID=1000
MemoryCurrent=16777216
NRestarts=0
ActiveEnterTimestampMonotonic=5000000000
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
        mariadb.service) printf 'failed' ;;
        redis-server.service) printf 'inactive' ;;
        *) printf 'active' ;;
    esac
}

mst_services_systemctl_is_enabled() {
    case "${1}" in
        redis-server.service) printf 'disabled' ;;
        *) printf 'enabled' ;;
    esac
}

mst_services_collect_report
python - <<'PY'
import json, os
report = json.loads(os.environ["MST_SERVICES_REPORT_JSON"])
assert report["document_type"] == "report"
assert report["command"] == "services"
assert len(report["records"]) == 7
assert report["aggregate"]["record_count"] == 7
assert report["aggregate"]["module_summaries"][0]["module"] == "services"
assert report["aggregate"]["overall_status"] == "critical"
records = {record["result_id"]: record for record in report["records"]}
assert records["res_services.redis"]["status"] == "warn"
assert records["res_services.database"]["status"] == "critical"
PY

mst_services_collect_service() {
    local service_id="${1:?service id required}"
    local record_name="${2:?record name required}"
    local details_name="${3:?details name required}"
    local errors_name="${4:?errors name required}"
    local rows_name="${5:?rows name required}"

    if [[ "${service_id}" == "database" ]]; then
        return 1
    fi

    local -n record_ref="${record_name}"
    local -n details_ref="${details_name}"
    local -n rows_ref="${rows_name}"
    record_ref=()
    details_ref=()
    rows_ref=()
    mst_services_record_init "${record_name}" "res_services.${service_id}" "${service_id}" "stub"
    record_ref[status]="ok"
    record_ref[severity]="ok"
    record_ref[summary]="${service_id} ok"
    mst_services_record_finalize "${record_name}" "$(mst_mrrf_now_epoch_ms)"
}

mst_services_collect_report
python - <<'PY'
import json, os
report = json.loads(os.environ["MST_SERVICES_REPORT_JSON"])
records = {record["result_id"]: record for record in report["records"]}
assert records["res_services.database"]["status"] == "unknown"
assert any(error["code"] == "COLLECTOR_FAILURE" for error in records["res_services.database"]["errors"])
PY

printf 'test_services_report.sh passed.\n'
