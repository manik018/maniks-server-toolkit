#!/usr/bin/env bash
# Shared helpers for the security events module.

if [[ -n "${MST_SECURITY_EVENTS_COMMON_LOADED:-}" ]]; then
    return
fi
readonly MST_SECURITY_EVENTS_COMMON_LOADED=1

mst_security_events_collect() {
    local record_name="${1:?record name required}"
    local details_name="${2:?details array name required}"
    local errors_name="${3:?errors array name required}"
    local started_ms
    local -n record_ref="${record_name}"
    local -n details_ref="${details_name}"
    local -n errors_ref="${errors_name}"

    started_ms="$(mst_mrrf_now_epoch_ms)"
    record_ref=()
    details_ref=()
    errors_ref=()
    record_ref[result_id]="res_security_events.module_status"
    record_ref[module]="security_events"
    record_ref[check]="module_status"
    record_ref[target]="security_events"
    record_ref[status]="ok"
    record_ref[severity]="ok"
    record_ref[score]="null"
    record_ref[summary]="Security events module is enabled with no checks implemented yet."
    record_ref[source_list]="derived"
    record_ref[provenance]="Module scaffold placeholder."
    record_ref[privilege_requirement]="none"
    record_ref[redactions_present]="false"
    record_ref[duration_ms]="$(( $(mst_mrrf_now_epoch_ms) - started_ms ))"
    record_ref[observed_at]="$(mst_mrrf_now_utc)"
}
