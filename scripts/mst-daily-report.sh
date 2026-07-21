#!/usr/bin/env bash
# Daily cron entrypoint: refresh MRRF1 reports and deliver the unified report.
set -u

MST_BIN="${MST_BIN:-/usr/local/bin/mst}"

if [[ ! -x "${MST_BIN}" ]]; then
    printf 'MST binary is not executable: %s\n' "${MST_BIN}" >&2
    exit 1
fi

"${MST_BIN}" health >/dev/null 2>&1 || true
"${MST_BIN}" services >/dev/null 2>&1 || true
"${MST_BIN}" security >/dev/null 2>&1 || true
"${MST_BIN}" website >/dev/null 2>&1 || true
"${MST_BIN}" wordpress >/dev/null 2>&1 || true
"${MST_BIN}" backup >/dev/null 2>&1 || true
"${MST_BIN}" alert >/dev/null 2>&1 || true

report_output="$("${MST_BIN}" report --style digest 2>/dev/null)"

if [[ -z "${report_output}" ]]; then
    printf 'MST unified report output is empty.\n' >&2
    exit 1
fi

printf '%s\n' "${report_output}" | "${MST_BIN}" telegram
telegram_status="${PIPESTATUS[1]}"
if [[ "${telegram_status}" -ne 0 ]]; then
    exit "${telegram_status}"
fi

if "${MST_BIN}" alert --has-confirmed-active-issue >/dev/null 2>&1; then
    critical_output="$("${MST_BIN}" report --style critical 2>/dev/null)"
    if [[ -z "${critical_output}" ]]; then
        printf 'MST unified report output is empty.\n' >&2
        exit 1
    fi
    printf '%s\n' "${critical_output}" | "${MST_BIN}" telegram
    telegram_status="${PIPESTATUS[1]}"
    if [[ "${telegram_status}" -ne 0 ]]; then
        exit "${telegram_status}"
    fi
fi
