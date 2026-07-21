#!/usr/bin/env bash
# Validate that the daily report only sends the critical template for confirmed active alerts.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/daily-report-alert-threshold"
STUB_BIN="${TMP_DIR}/mst"
STATE_FILE="${TMP_DIR}/alert.state"
TELEGRAM_LOG="${TMP_DIR}/telegram.log"
ALERT_DELIVERY_LOG="${TMP_DIR}/alert-delivery.log"

rm -rf -- "${TMP_DIR}"
mkdir -p -- "${TMP_DIR}"
trap 'rm -rf -- "${TMP_DIR}"' EXIT INT TERM

cat > "${STUB_BIN}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

subcommand="${1:-}"
state_file="${MST_DAILY_ALERT_STATE_FILE:?state file required}"
telegram_log="${MST_DAILY_TELEGRAM_LOG:?telegram log required}"
alert_delivery_log="${MST_DAILY_ALERT_DELIVERY_LOG:?alert delivery log required}"
scenario_status="${MST_DAILY_SCENARIO_STATUS:?scenario status required}"

load_state() {
    occurrence_count=0
    confirmed=false
    active=false
    previous_status=ok
    if [[ -f "${state_file}" ]]; then
        IFS='|' read -r occurrence_count confirmed active previous_status < "${state_file}"
    fi
}

save_state() {
    printf '%s|%s|%s|%s\n' "${occurrence_count}" "${confirmed}" "${active}" "${previous_status}" > "${state_file}"
}

case "${subcommand}" in
    health|services|security|website|wordpress|backup)
        exit 0
        ;;
    alert)
        load_state
        if [[ "${2:-}" == "--has-confirmed-active-issue" ]]; then
            [[ "${active}" == "true" && "${confirmed}" == "true" ]] && exit 0
            exit 1
        fi
        if [[ "${scenario_status}" == "critical" ]]; then
            if [[ "${active}" == "true" ]]; then
                occurrence_count=$((occurrence_count + 1))
            else
                occurrence_count=1
            fi
            active=true
            previous_status=critical
            if (( occurrence_count >= 2 )); then
                confirmed=true
            fi
            save_state
            exit 7
        fi
        if [[ "${scenario_status}" == "ok" ]]; then
            if [[ "${active}" == "true" ]]; then
                printf 'RECOVERY\n' >> "${alert_delivery_log}"
            fi
            occurrence_count=0
            confirmed=false
            active=false
            previous_status=ok
            save_state
            exit 7
        fi
        exit 99
        ;;
    report)
        [[ "${2:-}" == "--style" ]] || exit 98
        case "${3:-}" in
            digest) printf 'DIGEST:%s\n' "${scenario_status}" ;;
            critical) printf 'CRITICAL:%s\n' "${scenario_status}" ;;
            *) exit 97 ;;
        esac
        exit 0
        ;;
    telegram)
        {
            printf -- '---MESSAGE---\n'
            cat
        } >> "${telegram_log}"
        exit 0
        ;;
    *)
        printf 'unexpected subcommand: %s\n' "${subcommand}" >&2
        exit 99
        ;;
esac
EOF
chmod 0755 "${STUB_BIN}"

run_daily_for_status() {
    local status_name="${1:?status required}"
    MST_BIN="${STUB_BIN}" \
        MST_DAILY_ALERT_STATE_FILE="${STATE_FILE}" \
        MST_DAILY_TELEGRAM_LOG="${TELEGRAM_LOG}" \
        MST_DAILY_ALERT_DELIVERY_LOG="${ALERT_DELIVERY_LOG}" \
        MST_DAILY_SCENARIO_STATUS="${status_name}" \
        bash "${ROOT_DIR}/scripts/mst-daily-report.sh"
}

count_telegram_messages() {
    grep -c -- '^---MESSAGE---$' "${TELEGRAM_LOG}"
}

rm -f -- "${TELEGRAM_LOG}" "${ALERT_DELIVERY_LOG}"
run_daily_for_status critical
[[ "$(count_telegram_messages)" == "1" ]] || exit 1
grep -q 'DIGEST:critical' "${TELEGRAM_LOG}" || exit 1
if grep -q 'CRITICAL:critical' "${TELEGRAM_LOG}"; then
    exit 1
fi

rm -f -- "${TELEGRAM_LOG}" "${ALERT_DELIVERY_LOG}"
run_daily_for_status critical
[[ "$(count_telegram_messages)" == "2" ]] || exit 1
grep -q 'DIGEST:critical' "${TELEGRAM_LOG}" || exit 1
grep -q 'CRITICAL:critical' "${TELEGRAM_LOG}" || exit 1

rm -f -- "${TELEGRAM_LOG}" "${ALERT_DELIVERY_LOG}"
run_daily_for_status ok
[[ "$(count_telegram_messages)" == "1" ]] || exit 1
grep -q 'DIGEST:ok' "${TELEGRAM_LOG}" || exit 1
if grep -q 'CRITICAL:ok' "${TELEGRAM_LOG}"; then
    exit 1
fi
grep -q '^RECOVERY$' "${ALERT_DELIVERY_LOG}" || exit 1

printf 'test_daily_report_alert_threshold.sh passed.\n'
