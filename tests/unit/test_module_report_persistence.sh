#!/usr/bin/env bash
# Validate module commands persist normalized MRRF1 reports for unified aggregation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/module-report-persistence"
STATE_DIR="${TMP_DIR}/state"

rm -rf -- "${TMP_DIR}"
mkdir -p -- "${STATE_DIR}/reports"
trap 'rm -rf -- "${TMP_DIR}"' EXIT INT TERM

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/lib/report.sh"

export MST_STATE_DIR="${STATE_DIR}"
export MST_OUTPUT_MODE="text"

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

mst_log() {
    return 0
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

# shellcheck source=commands/services.sh
source "${ROOT_DIR}/commands/services.sh"
# shellcheck source=commands/security.sh
source "${ROOT_DIR}/commands/security.sh"
# shellcheck source=commands/website.sh
source "${ROOT_DIR}/commands/website.sh"
# shellcheck source=commands/wordpress.sh
source "${ROOT_DIR}/commands/wordpress.sh"
# shellcheck source=commands/backup.sh
source "${ROOT_DIR}/commands/backup.sh"

mst_services_collect_report() {
    MST_SERVICES_REPORT_JSON="$(make_report services nginx "Persisted services report")"
    MST_SERVICES_REPORT_EXIT_CODE=0
    export MST_SERVICES_REPORT_JSON MST_SERVICES_REPORT_EXIT_CODE
}

mst_security_collect_report() {
    MST_SECURITY_REPORT_JSON="$(make_report security ssh "Persisted security report")"
    MST_SECURITY_REPORT_EXIT_CODE=0
    export MST_SECURITY_REPORT_JSON MST_SECURITY_REPORT_EXIT_CODE
}

mst_website_collect_report() {
    MST_WEBSITE_REPORT_JSON="$(make_report website homepage "Persisted website report")"
    MST_WEBSITE_REPORT_EXIT_CODE=0
    export MST_WEBSITE_REPORT_JSON MST_WEBSITE_REPORT_EXIT_CODE
}

mst_wordpress_collect_report() {
    MST_WORDPRESS_REPORT_JSON="$(make_report wordpress site "Persisted WordPress report")"
    MST_WORDPRESS_REPORT_EXIT_CODE=0
    export MST_WORDPRESS_REPORT_JSON MST_WORDPRESS_REPORT_EXIT_CODE
}

mst_backup_collect_report() {
    MST_BACKUP_REPORT_JSON="$(make_report backup local "Persisted backup report")"
    MST_BACKUP_REPORT_EXIT_CODE=0
    export MST_BACKUP_REPORT_JSON MST_BACKUP_REPORT_EXIT_CODE
}

mst_render_services_report_text() { return 0; }
mst_render_security_report_text() { return 0; }
mst_render_website_report_text() { return 0; }
mst_render_wordpress_report_text() { return 0; }
mst_render_backup_report_text() { return 0; }

mst_command_services_run >/dev/null
mst_command_security_run >/dev/null
mst_command_website_run >/dev/null
mst_command_wordpress_run >/dev/null
mst_command_backup_run >/dev/null

for module_name in services security website wordpress backup; do
    report_file="${STATE_DIR}/reports/${module_name}.mrrf1.json"
    [[ -f "${report_file}" ]] || {
        printf 'missing persisted report: %s\n' "${report_file}" >&2
        exit 1
    }
    grep -F "\"command\":\"${module_name}\"" "${report_file}" >/dev/null || exit 1
done

unset MST_HEALTH_REPORT_JSON MST_SERVICES_REPORT_JSON MST_SECURITY_REPORT_JSON
unset MST_WEBSITE_REPORT_JSON MST_WORDPRESS_REPORT_JSON MST_BACKUP_REPORT_JSON

mst_report_collect
[[ "${MST_REPORT_TOTAL_OK}" == "5" ]] || exit 1
[[ "${MST_REPORT_TOTAL_UNAVAILABLE}" == "1" ]] || exit 1
printf '%s\n' "${MST_REPORT_RECORD_ROWS[@]}" | grep -F "Persisted services report" >/dev/null || exit 1
printf '%s\n' "${MST_REPORT_RECORD_ROWS[@]}" | grep -F "Persisted security report" >/dev/null || exit 1
printf '%s\n' "${MST_REPORT_RECORD_ROWS[@]}" | grep -F "Persisted website report" >/dev/null || exit 1
printf '%s\n' "${MST_REPORT_RECORD_ROWS[@]}" | grep -F "Persisted WordPress report" >/dev/null || exit 1
printf '%s\n' "${MST_REPORT_RECORD_ROWS[@]}" | grep -F "Persisted backup report" >/dev/null || exit 1

printf 'test_module_report_persistence.sh passed.\n'
