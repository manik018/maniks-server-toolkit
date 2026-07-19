#!/usr/bin/env bash
# MST services command.

if [[ -z "${MST_SERVICES_COMMAND_LOADED:-}" ]]; then
    readonly MST_SERVICES_COMMAND_LOADED=1
    # shellcheck source=inspectors/services.sh
    source "${MST_INSPECTOR_DIR}/services.sh"
    # shellcheck source=renderers/services_text.sh
    source "${MST_RENDERER_DIR}/services_text.sh"
fi

# Run the local services snapshot.
mst_command_services_run() {
    if [[ "${MST_OUTPUT_MODE}" != "text" ]]; then
        mst_die "${MST_EXIT_USAGE}" "Services module supports text output only in v1"
    fi

    mst_services_collect_report
    mst_render_services_report_text
    mst_log INFO services SERVICES_REPORT "Services module completed with exit code ${MST_SERVICES_REPORT_EXIT_CODE}"
    return "${MST_SERVICES_REPORT_EXIT_CODE}"
}
