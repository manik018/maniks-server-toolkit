#!/usr/bin/env bash
# Text renderer for alert policy decisions.

if [[ -n "${MST_ALERT_RENDERER_LOADED:-}" ]]; then
    return
fi
readonly MST_ALERT_RENDERER_LOADED=1

# Render all alert events.
mst_render_alert_report_text() {
    local row event_id module_name record_key current previous transition first_seen last_seen occurrence reason summary should_deliver suppressed suppression recovery timestamp

    mst_header "$(mst_version_string)"
    mst_section "Alert Decisions"
    mst_table_row "Total events" "${MST_ALERT_TOTAL_EVENTS:-0}"
    mst_table_row "Deliverable" "${MST_ALERT_DELIVERABLE_EVENTS:-0}"
    mst_table_row "Suppressed" "${MST_ALERT_SUPPRESSED_EVENTS:-0}"
    mst_table_row "Recoveries" "${MST_ALERT_RECOVERY_EVENTS:-0}"
    mst_table_row "Invalid input/state" "${MST_ALERT_INVALID_EVENTS:-0}"

    printf '  %-10s %-11s %-10s %-11s %-9s %s\n' "Module" "Transition" "Status" "Deliver" "Suppressed" "Summary"
    for row in "${MST_ALERT_EVENTS[@]:-}"; do
        IFS="${MST_MRRF_FIELD_SEPARATOR}" read -r event_id module_name record_key current previous transition first_seen last_seen occurrence reason summary should_deliver suppressed suppression recovery timestamp <<< "${row}"
        printf '  %-10s %-11s %-10s %-11s %-9s %s\n' \
            "${module_name}" \
            "${transition}" \
            "$(mst_alert_status_label "${current}")" \
            "${should_deliver}" \
            "${suppressed}" \
            "${summary}"
    done
}
