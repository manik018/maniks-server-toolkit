#!/usr/bin/env bash
# Validate security_events terminal status badges.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"

mst_header() { :; }
mst_section() { :; }
mst_status_badge() { printf '[%s]' "${1}"; }
source "${ROOT_DIR}/renderers/security_events_text.sh"

declare -gA MST_SECURITY_EVENTS_MODULE_STATUS_RECORD=()

MST_SECURITY_EVENTS_MODULE_STATUS_RECORD[status]="warn"
MST_SECURITY_EVENTS_MODULE_STATUS_RECORD[summary]="Warning summary."
warn_output="$(mst_render_security_events_report_text)"
[[ "${warn_output}" == *"[WARNING] Warning summary."* ]] || exit 1
[[ "${warn_output}" != *"[SUCCESS]"* ]] || exit 1

MST_SECURITY_EVENTS_MODULE_STATUS_RECORD[status]="unavailable"
MST_SECURITY_EVENTS_MODULE_STATUS_RECORD[summary]="Unavailable summary."
unavailable_output="$(mst_render_security_events_report_text)"
[[ "${unavailable_output}" == *"[UNAVAILABLE] Unavailable summary."* ]] || exit 1
[[ "${unavailable_output}" != *"[OK]"* ]] || exit 1

printf 'test_security_events_renderer.sh passed.\n'
