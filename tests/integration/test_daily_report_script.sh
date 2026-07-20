#!/usr/bin/env bash
# Validate the daily report cron orchestrator command order and delivery stdin.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/daily-report-script"
STUB_BIN="${TMP_DIR}/mst"
LOG_FILE="${TMP_DIR}/commands.log"
TELEGRAM_STDIN_FILE="${TMP_DIR}/telegram.stdin"

rm -rf -- "${TMP_DIR}"
mkdir -p -- "${TMP_DIR}"
trap 'rm -rf -- "${TMP_DIR}"' EXIT INT TERM

cat > "${STUB_BIN}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

subcommand="${1:-}"
printf '%s\n' "${subcommand}" >> "${MST_DAILY_LOG_FILE:?log file required}"

case "${subcommand}" in
    health|services|security|website|wordpress|backup)
        exit 7
        ;;
    report)
        printf 'REPORT BODY\n'
        exit 7
        ;;
    telegram)
        cat > "${MST_DAILY_TELEGRAM_STDIN_FILE:?stdin file required}"
        exit 23
        ;;
    *)
        printf 'unexpected subcommand: %s\n' "${subcommand}" >&2
        exit 99
        ;;
esac
EOF
chmod 0755 "${STUB_BIN}"

set +e
MST_BIN="${STUB_BIN}" \
    MST_DAILY_LOG_FILE="${LOG_FILE}" \
    MST_DAILY_TELEGRAM_STDIN_FILE="${TELEGRAM_STDIN_FILE}" \
    bash "${ROOT_DIR}/scripts/mst-daily-report.sh"
status=$?
set -e

[[ "${status}" -eq 23 ]] || {
    printf 'expected daily report script to exit with telegram status 23, got %s\n' "${status}" >&2
    exit 1
}

expected_order=$'health\nservices\nsecurity\nwebsite\nwordpress\nbackup\nreport\ntelegram'
actual_order="$(cat "${LOG_FILE}")"
[[ "${actual_order}" == "${expected_order}" ]] || {
    printf 'unexpected command order:\n%s\n' "${actual_order}" >&2
    exit 1
}

actual_telegram_stdin="$(cat "${TELEGRAM_STDIN_FILE}")"
[[ "${actual_telegram_stdin}" == "REPORT BODY" ]] || {
    printf 'unexpected telegram stdin: %s\n' "${actual_telegram_stdin}" >&2
    exit 1
}

printf 'test_daily_report_script.sh passed.\n'
