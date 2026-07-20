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

report_output="$("${MST_BIN}" report --style auto 2>/dev/null)"

if [[ -z "${report_output}" ]]; then
    printf 'MST unified report output is empty.\n' >&2
    exit 1
fi

printf '%s\n' "${report_output}" | "${MST_BIN}" telegram
