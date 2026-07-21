#!/usr/bin/env bash
# Validate persisted Health MRRF1 data across separate command processes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/persisted-health-pipeline"
STATE_DIR="${TMP_DIR}/state"
PROC_DIR="${TMP_DIR}/proc"
OS_RELEASE_FILE="${TMP_DIR}/os-release"

rm -rf -- "${TMP_DIR}"
mkdir -p -- "${STATE_DIR}" "${PROC_DIR}/sys/kernel" "${PROC_DIR}/self"
trap 'rm -rf -- "${TMP_DIR}"' EXIT INT TERM

cat > "${PROC_DIR}/loadavg" <<'EOF'
0.10 0.20 0.30 1/100 1234
EOF

cat > "${PROC_DIR}/meminfo" <<'EOF'
MemTotal:       2097152 kB
MemFree:        1048576 kB
MemAvailable:  1572864 kB
Buffers:          65536 kB
Cached:          262144 kB
SReclaimable:     65536 kB
SwapTotal:       524288 kB
SwapFree:        524288 kB
EOF

cat > "${PROC_DIR}/uptime" <<'EOF'
3600.00 1000.00
EOF

cat > "${PROC_DIR}/stat" <<'EOF'
cpu  100 0 100 700 0 0 0 0 0 0
btime 1710000000
EOF

cat > "${PROC_DIR}/sys/kernel/hostname" <<'EOF'
pipeline-host
EOF

cat > "${PROC_DIR}/sys/kernel/osrelease" <<'EOF'
6.8.0-31-generic
EOF

cat > "${PROC_DIR}/self/mounts" <<'EOF'
/dev/sda1 / ext4 rw,relatime 0 0
EOF

cat > "${OS_RELEASE_FILE}" <<'EOF'
NAME="Ubuntu"
VERSION_ID="24.04"
EOF

run_health_process() {
    (
        set -euo pipefail
        source "${ROOT_DIR}/lib/bootstrap.sh"
        mst_bootstrap "${ROOT_DIR}"
        mst_fs_validate_runtime_file_path() {
            local path="${1:?path required}"
            [[ "${path}" == "${STATE_DIR}"/* ]] || return 1
            [[ ! -L "${path}" ]] || return 1
            [[ -e "${path}" && ! -f "${path}" ]] && return 1
            printf '%s' "${path}"
        }
        mst_fs_validate_runtime_directory() {
            local path="${1:?path required}"
            [[ "${path}" == "${STATE_DIR}" || "${path}" == "${STATE_DIR}"/* ]] || return 1
            [[ ! -L "${path}" ]] || return 1
            printf '%s' "${path}"
        }
        mst_lock_acquire_nonblocking() {
            return 0
        }
        mst_lock_write_metadata() {
            return 0
        }
        mst_lock_release() {
            return 0
        }
        export MST_STATE_DIR="${STATE_DIR}"
        export MST_OUTPUT_MODE="text"
        export MST_HEALTH_PROC_DIR="${PROC_DIR}"
        export MST_HEALTH_OS_RELEASE_FILE="${OS_RELEASE_FILE}"
        export MST_HEALTH_MOUNTS_FILE="${PROC_DIR}/self/mounts"
        export MST_HEALTH_CPU_SAMPLE_SLEEP="0"
        export MST_HEALTH_CPU_WARN_PERCENT="80"
        export MST_HEALTH_CPU_ERROR_PERCENT="95"
        export MST_HEALTH_MEMORY_WARN_PERCENT="85"
        export MST_HEALTH_MEMORY_ERROR_PERCENT="95"
        export MST_HEALTH_DISK_WARN_PERCENT="85"
        export MST_HEALTH_DISK_ERROR_PERCENT="95"
        source "${ROOT_DIR}/commands/health.sh"
        sleep() {
            cat > "${PROC_DIR}/stat" <<'EOF'
cpu  110 0 105 785 0 0 0 0 0 0
btime 1710000000
EOF
        }
        mst_health_disk_statfs() {
            printf '100000|50000|50000|4096|10000|5000'
        }
        mst_command_health_run
    )
}

run_report_process() {
    (
        set -euo pipefail
        source "${ROOT_DIR}/lib/bootstrap.sh"
        mst_bootstrap "${ROOT_DIR}"
        mst_fs_validate_runtime_file_path() {
            local path="${1:?path required}"
            [[ "${path}" == "${STATE_DIR}"/* ]] || return 1
            [[ ! -L "${path}" ]] || return 1
            [[ -e "${path}" && ! -f "${path}" ]] && return 1
            printf '%s' "${path}"
        }
        mst_fs_validate_runtime_directory() {
            local path="${1:?path required}"
            [[ "${path}" == "${STATE_DIR}" || "${path}" == "${STATE_DIR}"/* ]] || return 1
            [[ -d "${path}" ]] || return 1
            [[ ! -L "${path}" ]] || return 1
            printf '%s' "${path}"
        }
        mst_lock_acquire_nonblocking() {
            return 0
        }
        mst_lock_write_metadata() {
            return 0
        }
        mst_lock_release() {
            return 0
        }
        export MST_STATE_DIR="${STATE_DIR}"
        export MST_OUTPUT_MODE="text"
        if (($# > 0)); then
            export MST_HEALTH_REPORT_JSON="${1}"
        fi
        source "${ROOT_DIR}/commands/report.sh"
        mst_command_report_run
    )
}

run_alert_process() {
    (
        set -euo pipefail
        source "${ROOT_DIR}/lib/bootstrap.sh"
        mst_bootstrap "${ROOT_DIR}"
        mst_fs_validate_runtime_file_path() {
            local path="${1:?path required}"
            [[ "${path}" == "${STATE_DIR}"/* ]] || return 1
            [[ ! -L "${path}" ]] || return 1
            [[ -e "${path}" && ! -f "${path}" ]] && return 1
            printf '%s' "${path}"
        }
        mst_fs_validate_runtime_directory() {
            local path="${1:?path required}"
            [[ "${path}" == "${STATE_DIR}" || "${path}" == "${STATE_DIR}"/* ]] || return 1
            [[ -d "${path}" ]] || return 1
            [[ ! -L "${path}" ]] || return 1
            printf '%s' "${path}"
        }
        mst_lock_acquire_nonblocking() {
            return 0
        }
        mst_lock_write_metadata() {
            return 0
        }
        mst_lock_release() {
            return 0
        }
        export MST_STATE_DIR="${STATE_DIR}"
        export MST_OUTPUT_MODE="text"
        export MST_ALERTS_ENABLED="true"
        export MST_ALERT_ON_WARNING="true"
        export MST_ALERT_ON_ERROR="true"
        export MST_ALERT_ON_UNAVAILABLE="true"
        export MST_ALERT_ON_UNKNOWN="true"
        export MST_ALERT_MODULES="all"
        export MST_ALERT_MIN_OCCURRENCES_BEFORE_DELIVERY="2"
        export MST_ALERT_COOLDOWN_SECONDS="3600"
        export MST_ALERT_RECOVERY_ENABLED="true"
        export MST_ALERT_REPEAT_ENABLED="false"
        export MST_ALERT_REPEAT_INTERVAL_SECONDS="21600"
        export MST_ALERT_TEST_NOW_EPOCH="1784289600"
        source "${ROOT_DIR}/commands/alert.sh"
        mst_command_alert_run
    )
}

set +e
empty_report_output="$(run_report_process 2>&1)"
empty_report_status=$?
set -e
[[ "${empty_report_status}" -eq 7 ]] || exit 1
[[ "${empty_report_output}" == *"No normalized MRRF1 aggregate report was supplied for Health."* ]] || exit 1

set +e
health_output="$(run_health_process 2>&1)"
health_status=$?
set -e
[[ "${health_status}" -eq 0 ]] || exit 1
[[ "${health_output}" == *"Health"* ]] || exit 1
[[ -f "${STATE_DIR}/reports/health.mrrf1.json" ]] || exit 1

set +e
report_output="$(run_report_process 2>&1)"
report_status=$?
set -e
[[ "${report_status}" -eq 7 ]] || exit 1
[[ "${report_output}" == *"pipeline-host"* ]] || exit 1
[[ "${report_output}" == *"CPU"* ]] || exit 1

set +e
alert_output="$(run_alert_process 2>&1)"
alert_status=$?
set -e
[[ "${alert_status}" -eq 0 ]] || exit 1
[[ "${alert_output}" == *"Alert Decisions"* ]] || exit 1
[[ "${alert_output}" == *"CPU"* || "${alert_output}" == *"cpu"* ]] || exit 1

printf 'not-json\n' > "${STATE_DIR}/reports/health.mrrf1.json"
set +e
corrupt_report_output="$(run_report_process 2>&1)"
corrupt_report_status=$?
set -e
[[ "${corrupt_report_status}" -eq 7 ]] || exit 1
[[ "${corrupt_report_output}" == *"No normalized MRRF1 aggregate report was supplied for Health."* ]] || exit 1

MST_HEALTH_REPORT_JSON='{"schema_version":1,"document_type":"report","toolkit":"mst","toolkit_version":"test","command":"health","generated_at":"2026-07-18T00:00:00Z","host":{"hostname":"explicit"},"records":[{"result_id":"res_health.explicit","module":"health","check":"fixture","target":"explicit","status":"ok","severity":"ok","score":null,"summary":"Explicit health report","details":[],"recommendations":[],"metadata":{"source":["fixture"],"provenance":"fixture","privilege_requirement":"none","contains_sensitive_data":false,"redactions_present":false,"optional_dependencies":[]},"errors":[],"duration_ms":1,"observed_at":"2026-07-18T00:00:00Z"}],"aggregate":{"record_count":1,"overall_status":"ok","overall_severity":"ok","overall_score":null,"risk_level":"low","module_summaries":[{"module":"health","record_count":1,"status":"ok","severity":"ok","score":null}]},"exit_code":0}'
export MST_HEALTH_REPORT_JSON
set +e
explicit_report_output="$(run_report_process "${MST_HEALTH_REPORT_JSON}" 2>&1)"
explicit_report_status=$?
set -e
[[ "${explicit_report_status}" -eq 7 ]] || exit 1
[[ "${explicit_report_output}" == *"Explicit health report"* ]] || exit 1

printf 'test_persisted_health_pipeline.sh passed.\n'
