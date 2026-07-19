#!/usr/bin/env bash
# Validate unified report aggregation from MRRF1 fixtures.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/lib/report.sh"
source "${ROOT_DIR}/renderers/report_text.sh"

make_report() {
    local command_name="${1:?command required}"
    local overall_status="${2:?status required}"
    shift 2 || true
    local records=()
    local record_spec target_name status_name summary_text index=0

    for record_spec in "$@"; do
        index=$(( index + 1 ))
        IFS='|' read -r target_name status_name summary_text <<< "${record_spec}"
        records+=("$(printf '{"result_id":"res_%s.%s","module":"%s","check":"fixture","target":"%s","status":"%s","severity":"%s","score":null,"summary":"%s","details":[],"recommendations":[],"metadata":{"source":["fixture"],"provenance":"fixture","privilege_requirement":"none","contains_sensitive_data":false,"redactions_present":false,"optional_dependencies":[]},"errors":[],"duration_ms":1,"observed_at":"2026-07-17T00:00:00Z"}' "${command_name}" "${index}" "${command_name}" "${target_name}" "${status_name}" "${status_name}" "${summary_text}")")
    done

    printf '{"schema_version":1,"document_type":"report","toolkit":"mst","toolkit_version":"test","command":"%s","generated_at":"2026-07-17T00:00:00Z","host":{"hostname":"fixture"},"records":[%s],"aggregate":{"record_count":%s,"overall_status":"%s","overall_severity":"%s","overall_score":null,"risk_level":"low","module_summaries":[{"module":"%s","record_count":%s,"status":"%s","severity":"%s","score":null}]},"exit_code":0}' \
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

export MST_HEALTH_REPORT_JSON
export MST_SERVICES_REPORT_JSON
export MST_SECURITY_REPORT_JSON
export MST_WEBSITE_REPORT_JSON
export MST_WORDPRESS_REPORT_JSON
export MST_BACKUP_REPORT_JSON

MST_HEALTH_REPORT_JSON="$(make_report health ok 'cpu|ok|CPU healthy' 'memory|ok|Memory healthy')"
MST_SERVICES_REPORT_JSON="$(make_report services ok 'nginx|ok|nginx active')"
MST_SECURITY_REPORT_JSON="$(make_report security warn 'ssh|warn|Password auth enabled')"
MST_WEBSITE_REPORT_JSON="$(make_report website critical 'site|critical|Homepage failed')"
MST_WORDPRESS_REPORT_JSON="$(make_report wordpress unavailable 'wp|unavailable|WP-CLI unavailable')"
MST_BACKUP_REPORT_JSON="$(make_report backup unknown 'backup|unknown|Backup state unknown')"

mst_report_collect
[[ "${MST_REPORT_TOTAL_MODULES}" == "6" ]] || exit 1
[[ "${MST_REPORT_TOTAL_RECORDS}" == "7" ]] || exit 1
[[ "${MST_REPORT_TOTAL_OK}" == "3" ]] || exit 1
[[ "${MST_REPORT_TOTAL_WARN}" == "1" ]] || exit 1
[[ "${MST_REPORT_TOTAL_CRITICAL}" == "1" ]] || exit 1
[[ "${MST_REPORT_TOTAL_UNAVAILABLE}" == "1" ]] || exit 1
[[ "${MST_REPORT_TOTAL_UNKNOWN}" == "1" ]] || exit 1
[[ "${MST_REPORT_STATUS}" == "critical" ]] || exit 1

rendered_output="$(mst_render_report_text)"
[[ "${rendered_output}" == *"Unified Report"* ]] || exit 1
[[ "${rendered_output}" == *"Overall Summary"* ]] || exit 1
[[ "${rendered_output}" == *"SUCCESS count"* ]] || exit 1
if awk 'length($0) > 120 { exit 1 }' <<< "${rendered_output}"; then
    :
else
    printf 'rendered report contains overly wide lines.\n' >&2
    exit 1
fi

unset MST_BACKUP_REPORT_JSON
mst_report_collect
[[ "${MST_REPORT_TOTAL_UNAVAILABLE}" == "2" ]] || exit 1
[[ "${MST_REPORT_TOTAL_RECORDS}" == "7" ]] || exit 1

unset MST_HEALTH_REPORT_JSON MST_SERVICES_REPORT_JSON MST_SECURITY_REPORT_JSON MST_WEBSITE_REPORT_JSON MST_WORDPRESS_REPORT_JSON MST_BACKUP_REPORT_JSON
mst_report_collect
[[ "${MST_REPORT_TOTAL_MODULES}" == "6" ]] || exit 1
[[ "${MST_REPORT_TOTAL_RECORDS}" == "6" ]] || exit 1
[[ "${MST_REPORT_TOTAL_UNAVAILABLE}" == "6" ]] || exit 1
[[ "${MST_REPORT_STATUS}" == "unavailable" ]] || exit 1

MST_HEALTH_REPORT_JSON="$(make_report health ok 'cpu|ok|CPU healthy')"
MST_SERVICES_REPORT_JSON="$(make_report services ok 'nginx|ok|nginx active')"
MST_SECURITY_REPORT_JSON="$(make_report security ok 'ssh|ok|SSH healthy')"
MST_WEBSITE_REPORT_JSON="$(make_report website ok 'site|ok|Homepage healthy')"
MST_WORDPRESS_REPORT_JSON="$(make_report wordpress ok 'wp|ok|WordPress healthy')"
MST_BACKUP_REPORT_JSON="$(make_report backup ok 'backup|ok|Backup fresh')"
mst_report_collect
[[ "${MST_REPORT_STATUS}" == "ok" ]] || exit 1
[[ "${MST_REPORT_TOTAL_OK}" == "6" ]] || exit 1

MST_HEALTH_REPORT_JSON="$(make_report health critical 'cpu|critical|CPU failed')"
MST_SERVICES_REPORT_JSON="$(make_report services critical 'nginx|critical|nginx failed')"
MST_SECURITY_REPORT_JSON="$(make_report security critical 'ssh|critical|SSH failed')"
MST_WEBSITE_REPORT_JSON="$(make_report website critical 'site|critical|Homepage failed')"
MST_WORDPRESS_REPORT_JSON="$(make_report wordpress critical 'wp|critical|WordPress failed')"
MST_BACKUP_REPORT_JSON="$(make_report backup critical 'backup|critical|Backup failed')"
mst_report_collect
[[ "${MST_REPORT_STATUS}" == "critical" ]] || exit 1
[[ "${MST_REPORT_TOTAL_CRITICAL}" == "6" ]] || exit 1

MST_HEALTH_REPORT_JSON='{"schema_version":1,"document_type":"record"}'
mst_report_collect
[[ "${MST_REPORT_TOTAL_UNAVAILABLE}" == "1" ]] || exit 1

printf 'test_report_engine.sh passed.\n'
