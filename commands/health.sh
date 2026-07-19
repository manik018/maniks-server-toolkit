#!/usr/bin/env bash
# MST health command.

if [[ -z "${MST_HEALTH_COMMAND_LOADED:-}" ]]; then
    readonly MST_HEALTH_COMMAND_LOADED=1
    # shellcheck source=inspectors/health.sh
    source "${MST_INSPECTOR_DIR}/health.sh"
    # shellcheck source=renderers/health_text.sh
    source "${MST_RENDERER_DIR}/health_text.sh"
fi

# Run the local operating-system health snapshot.
mst_command_health_execute() {
    if [[ "${MST_OUTPUT_MODE}" != "text" ]]; then
        mst_die "${MST_EXIT_USAGE}" "Health module supports text output only in v1"
    fi

    mst_health_collect_report
    mst_state_save_report health "${MST_HEALTH_REPORT_JSON:-}" || mst_log WARN health HEALTH_STATE "Health report state could not be persisted"
    mst_render_health_report_text
    mst_log INFO health HEALTH_REPORT "Health module completed with exit code ${MST_HEALTH_REPORT_EXIT_CODE}"
    return "${MST_HEALTH_REPORT_EXIT_CODE}"
}

mst_command_health_run() {
    mst_command_run_with_lock health mst_command_health_execute "$@"
}
