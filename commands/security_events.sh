#!/usr/bin/env bash
# MST security events command.

if [[ -z "${MST_SECURITY_EVENTS_COMMAND_LOADED:-}" ]]; then
    readonly MST_SECURITY_EVENTS_COMMAND_LOADED=1
    # shellcheck source=inspectors/security_events.sh
    source "${MST_INSPECTOR_DIR}/security_events.sh"
    # shellcheck source=renderers/security_events_text.sh
    source "${MST_RENDERER_DIR}/security_events_text.sh"
fi

mst_command_security_events_execute() {
    if [[ "${MST_OUTPUT_MODE}" != "text" ]]; then
        mst_die "${MST_EXIT_USAGE}" "Security events module supports text output only in v1"
    fi

    mst_security_events_collect_report
    mst_state_save_report security_events "${MST_SECURITY_EVENTS_REPORT_JSON:-}" || mst_log WARN security_events SECURITY_EVENTS_STATE "Security events report state could not be persisted"
    mst_render_security_events_report_text
    mst_log INFO security_events SECURITY_EVENTS_REPORT "Security events module completed with exit code ${MST_SECURITY_EVENTS_REPORT_EXIT_CODE}"
    return "${MST_SECURITY_EVENTS_REPORT_EXIT_CODE}"
}

mst_command_security_events_run() {
    mst_command_run_with_lock security_events mst_command_security_events_execute "$@"
}
