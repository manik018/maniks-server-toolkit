#!/usr/bin/env bash
# Validate MRRF1 control-character sanitization and JSON escaping.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=lib/mrrf.sh
source "${ROOT_DIR}/lib/mrrf.sh"

control_value=$'A\x1bB\x01C\x0bD\x7fE'
sanitized="$(mst_mrrf_sanitize_text "${control_value}" 200)"
escaped="$(mst_mrrf_json_escape "${sanitized}")"
json_document="{\"v\":\"${escaped}\"}"

printf '%s\n' "${json_document}" | python3 -m json.tool >/dev/null
[[ "${sanitized}" == "ABCDE" ]] || exit 1
[[ "${escaped}" != *$'\x1b'* ]] || exit 1

[[ "$(mst_mrrf_sanitize_text $'line one\nline two' 200)" == "line one line two" ]] || exit 1
[[ "$(mst_mrrf_sanitize_text 'normal text' 200)" == "normal text" ]] || exit 1
[[ "$(mst_mrrf_sanitize_text 'a\b' 200)" == 'a\\b' ]] || exit 1
[[ "$(mst_mrrf_json_escape 'a"b')" == 'a\"b' ]] || exit 1
[[ "$(mst_mrrf_json_escape 'a\b')" == 'a\\b' ]] || exit 1
[[ "$(mst_mrrf_json_escape $'a\nb')" == 'a\nb' ]] || exit 1

printf 'test_mrrf_control_characters.sh passed.\n'
