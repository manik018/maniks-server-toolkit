#!/usr/bin/env bash
# MST security command.

if [[ -z "${MST_SECURITY_COMMAND_LOADED:-}" ]]; then
    readonly MST_SECURITY_COMMAND_LOADED=1
    # shellcheck source=inspectors/security.sh
    source "${MST_INSPECTOR_DIR}/security.sh"
    # shellcheck source=renderers/security_text.sh
    source "${MST_RENDERER_DIR}/security_text.sh"
fi

# Run the local security posture snapshot.
mst_command_security_run() {
    if [[ "${MST_OUTPUT_MODE}" != "text" ]]; then
        mst_die "${MST_EXIT_USAGE}" "Security module supports text output only in v1"
    fi

    mst_security_collect_report
    mst_state_save_report security "${MST_SECURITY_REPORT_JSON:-}" || mst_log WARN security SECURITY_STATE "Security report state could not be persisted"
    mst_render_security_report_text
    mst_log INFO security SECURITY_REPORT "Security module completed with exit code ${MST_SECURITY_REPORT_EXIT_CODE}"
    return "${MST_SECURITY_REPORT_EXIT_CODE}"
}
