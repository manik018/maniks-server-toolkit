#!/usr/bin/env bash
# Validate Telegram-friendly unified report styles.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/report-telegram-renderer"

rm -rf -- "${TMP_DIR}"
mkdir -p -- "${TMP_DIR}/state"
trap 'rm -rf -- "${TMP_DIR}"' EXIT INT TERM

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/commands/report.sh"

export MST_OUTPUT_MODE="text"
export MST_STATE_DIR="${TMP_DIR}/state"

make_record() {
    local command_name="${1:?command required}"
    local result_suffix="${2:?suffix required}"
    local check_name="${3:?check required}"
    local target_name="${4:?target required}"
    local status_name="${5:?status required}"
    local summary_text="${6:?summary required}"
    local details_json="${7:-[]}"

    printf '{"result_id":"res_%s.%s","module":"%s","check":"%s","target":"%s","status":"%s","severity":"%s","score":null,"summary":"%s","details":%s,"recommendations":[],"metadata":{"source":["fixture"],"provenance":"fixture","privilege_requirement":"none","contains_sensitive_data":false,"redactions_present":false,"optional_dependencies":[]},"errors":[],"duration_ms":1,"observed_at":"2026-07-17T00:00:00Z"}' \
        "${command_name}" "${result_suffix}" "${command_name}" "${check_name}" "${target_name}" "${status_name}" "${status_name}" "${summary_text}" "${details_json}"
}

make_report_from_records() {
    local command_name="${1:?command required}"
    local overall_status="${2:?status required}"
    shift 2 || true
    local records=("$@")

    printf '{"schema_version":1,"document_type":"report","toolkit":"mst","toolkit_version":"test","command":"%s","generated_at":"2026-07-17T00:00:00Z","host":{"hostname":"fixture-host"},"records":[%s],"aggregate":{"record_count":%s,"overall_status":"%s","overall_severity":"%s","overall_score":null,"risk_level":"low","module_summaries":[{"module":"%s","record_count":%s,"status":"%s","severity":"%s","score":null}]},"exit_code":0}' \
        "${command_name}" \
        "$(IFS=,; printf '%s' "${records[*]:-}")" \
        "${#records[@]}" \
        "${overall_status}" \
        "${overall_status}" \
        "${command_name}" \
        "${#records[@]}" \
        "${overall_status}" \
        "${overall_status}"
}

set_ok_fixture() {
    local cpu_details memory_record disk_details uptime_details
    cpu_details='[{"key":"cpu_percent","label":"CPU Utilization","value_type":"integer","value":12,"unit":"%","sensitive":false},{"key":"load_1m","label":"Load Average 1m","value_type":"string","value":"0.10","unit":"","sensitive":false},{"key":"load_5m","label":"Load Average 5m","value_type":"string","value":"0.20","unit":"","sensitive":false},{"key":"load_15m","label":"Load Average 15m","value_type":"string","value":"0.30","unit":"","sensitive":false}]'
    disk_details='[{"key":"fs_01","label":"Filesystem 1","value_type":"string","value":"/ /dev/sda1 1000MiB 200MiB 800MiB 20% inode 10%","unit":"","sensitive":false},{"key":"filesystem_count","label":"Filesystem Count","value_type":"integer","value":1,"unit":"","sensitive":false}]'
    uptime_details='[{"key":"uptime_seconds","label":"Uptime","value_type":"integer","value":3660,"unit":"seconds","sensitive":false}]'
    memory_record="$(make_record health memory memory_usage localhost ok 'Memory utilization is 30% with 700 MiB available.' '[]')"

    MST_HEALTH_REPORT_JSON="$(make_report_from_records health ok \
        "$(make_record health cpu cpu_usage localhost ok 'CPU utilization is 12% with load averages 0.10, 0.20, 0.30.' "${cpu_details}")" \
        "${memory_record}" \
        "$(make_record health disk disk_usage local_filesystems ok 'Observed 1 local filesystems; highest usage is 20%.' "${disk_details}")" \
        "$(make_record health uptime uptime localhost ok 'System uptime is 1h 1m since 2026-07-17T00:00:00Z.' "${uptime_details}")")"
    MST_SERVICES_REPORT_JSON="$(make_report_from_records services ok "$(make_record services nginx service_status Nginx ok 'Nginx active.' '[]')")"
    MST_SECURITY_REPORT_JSON="$(make_report_from_records security ok "$(make_record security ssh ssh_config SSH ok 'SSH healthy.' '[]')")"
    MST_WEBSITE_REPORT_JSON="$(make_report_from_records website ok "$(make_record website site http_check example.com ok 'Homepage healthy.' '[]')")"
    MST_WORDPRESS_REPORT_JSON="$(make_report_from_records wordpress ok "$(make_record wordpress wp wp_cli example.com ok 'WordPress healthy.' '[]')")"
    MST_BACKUP_REPORT_JSON="$(make_report_from_records backup ok "$(make_record backup local backup_age local ok 'Backup fresh.' '[]')")"
    export MST_HEALTH_REPORT_JSON MST_SERVICES_REPORT_JSON MST_SECURITY_REPORT_JSON MST_WEBSITE_REPORT_JSON MST_WORDPRESS_REPORT_JSON MST_BACKUP_REPORT_JSON
}

set_critical_fixture() {
    set_ok_fixture
    MST_SERVICES_REPORT_JSON="$(make_report_from_records services critical "$(make_record services nginx service_status Nginx critical 'Nginx inactive.' '[]')")"
    export MST_SERVICES_REPORT_JSON
}

capture_report() {
    local output status
    set +e
    output="$(mst_command_report_execute "$@")"
    status=$?
    set -e
    printf '%s' "${output}"
    return "${status}"
}

set_ok_fixture
set +e
telegram_output="$(capture_report --style telegram)"
telegram_status=$?
set -e
[[ "${telegram_status}" -eq 0 ]] || exit 1
[[ "${telegram_output}" == *"📍 Server"* ]] || exit 1
[[ "${telegram_output}" == *"🟢 Health"* ]] || exit 1
[[ "${telegram_output}" == *"Generated by Manik's Server Toolkit"* ]] || exit 1
[[ "${telegram_output}" == *"CPU: 12%"* ]] || exit 1

digest_output="$(capture_report --style digest)"
[[ "${digest_output}" == *"Daily Server Report"* ]] || exit 1
[[ "${digest_output}" == *"No critical issues detected."* ]] || exit 1

auto_ok_output="$(capture_report --style auto)"
[[ "${auto_ok_output}" == *"Daily Server Report"* ]] || exit 1

default_output="$(capture_report)"
[[ "${default_output}" == *"Unified Report"* ]] || exit 1
[[ "${default_output}" == *"Overall Summary"* ]] || exit 1

set_critical_fixture
set +e
critical_output="$(capture_report --style critical)"
critical_status=$?
set -e
[[ "${critical_status}" -eq "${MST_EXIT_PARTIAL}" ]] || exit 1
[[ "${critical_output}" == *"🔴 CRITICAL SERVER ALERT"* ]] || exit 1
[[ "${critical_output}" == *"❌ Nginx DOWN"* ]] || exit 1

set +e
auto_critical_output="$(capture_report --style auto)"
auto_critical_status=$?
set -e
[[ "${auto_critical_status}" -eq "${MST_EXIT_PARTIAL}" ]] || exit 1
[[ "${auto_critical_output}" == *"CRITICAL SERVER ALERT"* ]] || exit 1

set +e
invalid_output="$(mst_command_report_execute --style nope 2>/dev/null)"
invalid_status=$?
set -e
[[ -z "${invalid_output}" ]] || exit 1
[[ "${invalid_status}" -eq "${MST_EXIT_USAGE}" ]] || exit 1

printf 'test_report_telegram_renderer.sh passed.\n'
