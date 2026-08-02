#!/usr/bin/env bash
# Text renderer for the security events module scaffold.

if [[ -n "${MST_SECURITY_EVENTS_RENDERER_LOADED:-}" ]]; then
    return
fi
readonly MST_SECURITY_EVENTS_RENDERER_LOADED=1

mst_security_events_status_badge() {
    case "${1:-unknown}" in
        ok) mst_status_badge SUCCESS ;;
        warn) mst_status_badge WARNING ;;
        critical) mst_status_badge ERROR ;;
        unavailable) printf '[UNAVAILABLE]' ;;
        unknown|skipped) printf '[%s]' "${1^^}" ;;
        *) printf '[%s]' "${1^^}" ;;
    esac
}

mst_render_security_events_report_text() {
    local record_var
    mst_header "$(mst_version_string)"
    mst_section "Security Events"
    for record_var in "${MST_SECURITY_EVENTS_RECORD_VARS[@]}"; do
        local -n record_ref="${record_var}"
        printf '%s %s\n' "$(mst_security_events_status_badge "${record_ref[status]}")" "${record_ref[summary]}"
    done
}
