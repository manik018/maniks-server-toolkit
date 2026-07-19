#!/usr/bin/env bash
# Validate aggregate MRRF1 report generation and collector isolation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/health-report"
PROC_DIR="${TMP_DIR}/proc"

mkdir -p "${PROC_DIR}/sys/kernel" "${PROC_DIR}/self"

cat > "${PROC_DIR}/loadavg" <<'EOF'
1.00 0.50 0.25 1/100 1234
EOF

cat > "${PROC_DIR}/meminfo" <<'EOF'
MemTotal:       2097152 kB
MemFree:         262144 kB
MemAvailable:    524288 kB
Buffers:          65536 kB
Cached:          262144 kB
SReclaimable:     65536 kB
SwapTotal:       524288 kB
SwapFree:        131072 kB
EOF

cat > "${PROC_DIR}/uptime" <<'EOF'
3600.00 1000.00
EOF

cat > "${PROC_DIR}/stat" <<'EOF'
cpu  100 0 100 700 0 0 0 0 0 0
btime 1710000000
EOF

cat > "${PROC_DIR}/sys/kernel/hostname" <<'EOF'
ubuntu-report
EOF

cat > "${PROC_DIR}/sys/kernel/osrelease" <<'EOF'
6.8.0-31-generic
EOF

cat > "${PROC_DIR}/self/mounts" <<'EOF'
/dev/sda1 / ext4 rw,relatime 0 0
EOF

cat > "${TMP_DIR}/os-release" <<'EOF'
NAME="Ubuntu"
VERSION_ID="24.04"
EOF

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/inspectors/health.sh"

export MST_HEALTH_PROC_DIR="${PROC_DIR}"
export MST_HEALTH_OS_RELEASE_FILE="${TMP_DIR}/os-release"
export MST_HEALTH_MOUNTS_FILE="${PROC_DIR}/self/mounts"
export MST_HEALTH_CPU_SAMPLE_SLEEP="0"

sleep() {
    cat > "${PROC_DIR}/stat" <<'EOF'
cpu  150 0 120 730 0 0 0 0 0 0
btime 1710000000
EOF
}

mst_health_disk_statfs() {
    printf '100000|50000|50000|4096|10000|9000'
}

mst_health_collect_report
python - <<'PY'
import json, os
report = json.loads(os.environ["MST_HEALTH_REPORT_JSON"])
assert report["document_type"] == "report"
assert report["command"] == "health"
assert len(report["records"]) == 5
assert report["aggregate"]["record_count"] == 5
assert report["aggregate"]["module_summaries"][0]["module"] == "health"
assert report["aggregate"]["overall_score"] is None
assert report["records"][0]["module"] == "health"
PY

mst_health_collect_disk() {
    return 1
}
cat > "${PROC_DIR}/stat" <<'EOF'
cpu  100 0 100 700 0 0 0 0 0 0
btime 1710000000
EOF
mst_health_collect_report
python - <<'PY'
import json, os
report = json.loads(os.environ["MST_HEALTH_REPORT_JSON"])
records = {record["check"]: record for record in report["records"]}
assert len(report["records"]) == 5
assert records["disk"]["status"] == "unknown"
assert any(error["code"] == "COLLECTOR_FAILURE" for error in records["disk"]["errors"])
PY

printf 'test_health_report.sh passed.\n'
