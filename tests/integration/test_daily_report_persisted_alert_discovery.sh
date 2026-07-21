#!/usr/bin/env bash
# Validate daily alert confirmation discovers persisted website reports with zero alert arguments.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/daily-report-persisted-alert-discovery"
STATE_DIR="${TMP_DIR}/state"
STUB_BIN="${TMP_DIR}/mst"
TELEGRAM_LOG="${TMP_DIR}/telegram.log"

rm -rf -- "${TMP_DIR}"
mkdir -p -- "${TMP_DIR}" "${STATE_DIR}/reports"
trap 'rm -rf -- "${TMP_DIR}"' EXIT INT TERM

make_report() {
    local command_name="${1:?command required}"
    shift || true
    local records=()
    local record_spec result_id check_name target_name status_name summary_text worst_status="ok"

    for record_spec in "$@"; do
        IFS='|' read -r result_id check_name target_name status_name summary_text <<< "${record_spec}"
        records+=("$(printf '{"result_id":"%s","module":"%s","check":"%s","target":"%s","status":"%s","severity":"%s","score":null,"summary":"%s","details":[],"recommendations":[],"metadata":{"source":["fixture"],"provenance":"fixture","privilege_requirement":"none","contains_sensitive_data":false,"redactions_present":false,"optional_dependencies":[]},"errors":[],"duration_ms":1,"observed_at":"2026-07-18T00:00:00Z"}' "${result_id}" "${command_name}" "${check_name}" "${target_name}" "${status_name}" "${status_name}" "${summary_text}")")
        case "${status_name}" in
            critical) worst_status="critical" ;;
            unavailable) [[ "${worst_status}" != "critical" ]] && worst_status="unavailable" ;;
            unknown) [[ "${worst_status}" != "critical" && "${worst_status}" != "unavailable" ]] && worst_status="unknown" ;;
            warn) [[ "${worst_status}" == "ok" ]] && worst_status="warn" ;;
        esac
    done

    printf '{"schema_version":1,"document_type":"report","toolkit":"mst","toolkit_version":"test","command":"%s","generated_at":"2026-07-18T00:00:00Z","host":{"hostname":"fixture"},"records":[%s],"aggregate":{"record_count":%s,"overall_status":"%s","overall_severity":"%s","overall_score":null,"risk_level":"low","module_summaries":[{"module":"%s","record_count":%s,"status":"%s","severity":"%s","score":null}]},"exit_code":0}' \
        "${command_name}" \
        "$(IFS=,; printf '%s' "${records[*]:-}")" \
        "${#records[@]}" \
        "${worst_status}" \
        "${worst_status}" \
        "${command_name}" \
        "${#records[@]}" \
        "${worst_status}" \
        "${worst_status}"
}

make_report website 'res_website.site|http|example.test|critical|Persisted website failed' > "${STATE_DIR}/reports/website.mrrf1.json"

cat > "${STUB_BIN}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

subcommand="${1:-}"
case "${subcommand}" in
    health|services|security|website|wordpress|backup)
        exit 0
        ;;
    alert)
        shift || true
        (
            set -euo pipefail
            source "${MST_DAILY_ROOT_DIR:?root dir required}/lib/bootstrap.sh"
            mst_bootstrap "${MST_DAILY_ROOT_DIR}"
            mst_fs_validate_runtime_file_path() {
                local path="${1:?path required}"
                [[ "${path}" == "${MST_DAILY_STATE_DIR:?state dir required}"/* ]] || return 1
                [[ ! -L "${path}" ]] || return 1
                [[ -e "${path}" && ! -f "${path}" ]] && return 1
                printf '%s' "${path}"
            }
            mst_fs_validate_runtime_directory() {
                local path="${1:?path required}"
                [[ "${path}" == "${MST_DAILY_STATE_DIR:?state dir required}" || "${path}" == "${MST_DAILY_STATE_DIR}"/* ]] || return 1
                [[ -d "${path}" ]] || return 1
                [[ ! -L "${path}" ]] || return 1
                printf '%s' "${path}"
            }
            export MST_STATE_DIR="${MST_DAILY_STATE_DIR}"
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
            source "${MST_DAILY_ROOT_DIR}/commands/alert.sh"
            mst_command_alert_execute "$@"
        )
        ;;
    report)
        [[ "${2:-}" == "--style" ]] || exit 98
        case "${3:-}" in
            digest) printf 'DIGEST\n' ;;
            critical) printf 'CRITICAL\n' ;;
            *) exit 97 ;;
        esac
        ;;
    telegram)
        {
            printf -- '---MESSAGE---\n'
            cat
        } >> "${MST_DAILY_TELEGRAM_LOG:?telegram log required}"
        ;;
    *)
        printf 'unexpected subcommand: %s\n' "${subcommand}" >&2
        exit 99
        ;;
esac
EOF
chmod 0755 "${STUB_BIN}"

run_daily() {
    MST_BIN="${STUB_BIN}" \
        MST_DAILY_ROOT_DIR="${ROOT_DIR}" \
        MST_DAILY_STATE_DIR="${STATE_DIR}" \
        MST_DAILY_TELEGRAM_LOG="${TELEGRAM_LOG}" \
        bash "${ROOT_DIR}/scripts/mst-daily-report.sh"
}

count_telegram_messages() {
    grep -c -- '^---MESSAGE---$' "${TELEGRAM_LOG}"
}

rm -f -- "${TELEGRAM_LOG}"
run_daily
[[ "$(count_telegram_messages)" == "1" ]] || exit 1
grep -q '^DIGEST$' "${TELEGRAM_LOG}" || exit 1
if grep -q '^CRITICAL$' "${TELEGRAM_LOG}"; then
    exit 1
fi

rm -f -- "${TELEGRAM_LOG}"
run_daily
[[ "$(count_telegram_messages)" == "2" ]] || exit 1
grep -q '^DIGEST$' "${TELEGRAM_LOG}" || exit 1
grep -q '^CRITICAL$' "${TELEGRAM_LOG}" || exit 1

printf 'test_daily_report_persisted_alert_discovery.sh passed.\n'
