#!/usr/bin/env bash
# Validate health collectors against fixture data and failure modes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/health-collectors"
PROC_DIR="${TMP_DIR}/proc"

mkdir -p "${PROC_DIR}/sys/kernel" "${PROC_DIR}/self"

cat > "${PROC_DIR}/loadavg" <<'EOF'
0.40 0.20 0.10 1/100 1234
EOF

cat > "${PROC_DIR}/meminfo" <<'EOF'
MemTotal:       1048576 kB
MemFree:         131072 kB
MemAvailable:    524288 kB
Buffers:          65536 kB
Cached:          196608 kB
SReclaimable:     32768 kB
SwapTotal:       524288 kB
SwapFree:        262144 kB
EOF

cat > "${PROC_DIR}/uptime" <<'EOF'
7200.00 1000.00
EOF

cat > "${PROC_DIR}/stat" <<'EOF'
cpu  100 0 100 800 0 0 0 0 0 0
btime 1710000000
EOF

cat > "${PROC_DIR}/sys/kernel/hostname" <<'EOF'
ubuntu-test
EOF

cat > "${PROC_DIR}/sys/kernel/osrelease" <<'EOF'
6.8.0-31-generic
EOF

cat > "${PROC_DIR}/self/mounts" <<'EOF'
/dev/sda1 / ext4 rw,relatime 0 0
/dev/sda2 /var xfs rw,relatime 0 0
tmpfs /run tmpfs rw,nosuid,nodev 0 0
/dev/loop0 /snap/core squashfs ro,nodev 0 0
overlay /var/lib/docker/overlay2/abc overlay rw,relatime 0 0
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
cpu  120 0 120 960 0 0 0 0 0 0
btime 1710000000
EOF
}

mst_health_disk_statfs() {
    case "${1}" in
        /) printf '100000|60000|55000|4096|10000|9500' ;;
        /var) printf '50000|2500|2500|4096|5000|250' ;;
        *) return 1 ;;
    esac
}

declare -A cpu_record=()
declare -a cpu_details=() cpu_errors=() cpu_rows=()
mst_health_collect_cpu cpu_record cpu_details cpu_errors cpu_rows
[[ "${cpu_record[status]}" == "ok" ]] || exit 1

declare -A memory_record=()
declare -a memory_details=() memory_errors=() memory_rows=()
mst_health_collect_memory memory_record memory_details memory_errors memory_rows
[[ "${memory_record[status]}" == "ok" ]] || exit 1

declare -A disk_record=()
declare -a disk_details=() disk_errors=() disk_rows=()
mst_health_collect_disk disk_record disk_details disk_errors disk_rows
[[ "${disk_record[status]}" == "critical" ]] || exit 1
[[ "${#disk_rows[@]}" -eq 2 ]] || exit 1

declare -A uptime_record=()
declare -a uptime_details=() uptime_errors=() uptime_rows=()
mst_health_collect_uptime uptime_record uptime_details uptime_errors uptime_rows
[[ "${uptime_record[status]}" == "ok" ]] || exit 1

declare -A system_record=()
declare -a system_details=() system_errors=() system_rows=()
mst_health_collect_system system_record system_details system_errors system_rows
[[ "${system_record[status]}" == "ok" ]] || exit 1

# Permission failure path.
mst_health_cpu_read_stat_line() {
    return 1
}
mst_health_source_error_category() {
    printf 'permission'
}
declare -A permission_record=()
declare -a permission_details=() permission_errors=() permission_rows=()
mst_health_collect_cpu permission_record permission_details permission_errors permission_rows
[[ "${permission_record[status]}" == "unavailable" ]] || exit 1
[[ "${permission_errors[0]}" == permission* ]] || exit 1

unset -f mst_health_source_error_category
mst_health_source_error_category() {
    if [[ -e "${1}" ]] && [[ ! -r "${1}" ]]; then
        printf 'permission'
    else
        printf 'dependency'
    fi
}
unset -f mst_health_cpu_read_stat_line

# Missing proc data path.
mst_health_cpu_read_stat_line() {
    return 1
}
declare -A missing_record=()
declare -a missing_details=() missing_errors=() missing_rows=()
mst_health_collect_cpu missing_record missing_details missing_errors missing_rows
[[ "${missing_record[status]}" == "unavailable" ]] || exit 1
[[ "${missing_errors[0]}" == dependency* ]] || exit 1

# Malformed data path.
cat > "${PROC_DIR}/meminfo" <<'EOF'
MemTotal:       broken
EOF
declare -A malformed_record=()
declare -a malformed_details=() malformed_errors=() malformed_rows=()
mst_health_collect_memory malformed_record malformed_details malformed_errors malformed_rows
[[ "${malformed_record[status]}" == "unavailable" ]] || exit 1

printf 'test_health_collectors.sh passed.\n'
