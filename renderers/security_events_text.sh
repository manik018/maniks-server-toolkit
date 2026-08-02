#!/usr/bin/env bash
# Text renderer for the security events module scaffold.

if [[ -n "${MST_SECURITY_EVENTS_RENDERER_LOADED:-}" ]]; then
    return
fi
readonly MST_SECURITY_EVENTS_RENDERER_LOADED=1

mst_render_security_events_report_text() {
    mst_header "$(mst_version_string)"
    mst_section "Security Events"
    printf '%s %s\n' "$(mst_status_badge SUCCESS)" "${MST_SECURITY_EVENTS_MODULE_STATUS_RECORD[summary]}"
}
