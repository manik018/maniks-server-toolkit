#!/usr/bin/env bash
# Validate unified report discovery from persisted MRRF1 aggregate files.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/report-persisted-discovery"
STATE_DIR="${TMP_DIR}/state"

rm -rf -- "${TMP_DIR}"
mkdir -p -- "${STATE_DIR}/reports"
trap 'rm -rf -- "${TMP_DIR}"' EXIT INT TERM

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/lib/report.sh"

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

make_report() {
    local command_name="${1:?command required}"
    local target_name="${2:?target required}"
    local summary_text="${3:?summary required}"

    printf '{"schema_version":1,"document_type":"report","toolkit":"mst","toolkit_version":"test","command":"%s","generated_at":"2026-07-19T00:00:00Z","host":{"hostname":"persisted"},"records":[{"result_id":"res_%s.fixture","module":"%s","check":"fixture","target":"%s","status":"ok","severity":"ok","score":null,"summary":"%s","details":[],"recommendations":[],"metadata":{"source":["fixture"],"provenance":"fixture","privilege_requirement":"none","contains_sensitive_data":false,"redactions_present":false,"optional_dependencies":[]},"errors":[],"duration_ms":1,"observed_at":"2026-07-19T00:00:00Z"}],"aggregate":{"record_count":1,"overall_status":"ok","overall_severity":"ok","overall_score":null,"risk_level":"low","module_summaries":[{"module":"%s","record_count":1,"status":"ok","severity":"ok","score":null}]},"exit_code":0}' \
        "${command_name}" \
        "${command_name}" \
        "${command_name}" \
        "${target_name}" \
        "${summary_text}" \
        "${command_name}"
}

export MST_STATE_DIR="${STATE_DIR}"
unset MST_HEALTH_REPORT_JSON MST_SERVICES_REPORT_JSON MST_SECURITY_REPORT_JSON
unset MST_WEBSITE_REPORT_JSON MST_WORDPRESS_REPORT_JSON MST_BACKUP_REPORT_JSON

make_report health cpu "Persisted CPU healthy" > "${STATE_DIR}/reports/health.mrrf1.json"
make_report services nginx "Persisted nginx active" > "${STATE_DIR}/reports/services.mrrf1.json"

mst_report_collect

[[ "${MST_REPORT_TOTAL_MODULES}" == "6" ]] || exit 1
[[ "${MST_REPORT_TOTAL_RECORDS}" == "6" ]] || exit 1
[[ "${MST_REPORT_TOTAL_OK}" == "2" ]] || exit 1
[[ "${MST_REPORT_TOTAL_UNAVAILABLE}" == "4" ]] || exit 1
[[ "${MST_REPORT_STATUS}" == "unavailable" ]] || exit 1

printf '%s\n' "${MST_REPORT_RECORD_ROWS[@]}" | grep -F "Persisted CPU healthy" >/dev/null || exit 1
printf '%s\n' "${MST_REPORT_RECORD_ROWS[@]}" | grep -F "Persisted nginx active" >/dev/null || exit 1

printf 'test_report_persisted_discovery.sh passed.\n'
