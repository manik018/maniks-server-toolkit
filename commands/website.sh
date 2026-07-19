#!/usr/bin/env bash
# MST website command.

if [[ -z "${MST_WEBSITE_COMMAND_LOADED:-}" ]]; then
    readonly MST_WEBSITE_COMMAND_LOADED=1
    # shellcheck source=inspectors/website.sh
    source "${MST_INSPECTOR_DIR}/website.sh"
    # shellcheck source=renderers/website_text.sh
    source "${MST_RENDERER_DIR}/website_text.sh"
fi

# Run the local website monitoring snapshot.
mst_command_website_run() {
    if [[ "${MST_OUTPUT_MODE}" != "text" ]]; then
        mst_die "${MST_EXIT_USAGE}" "Website module supports text output only in v1"
    fi

    mst_website_collect_report
    mst_state_save_report website "${MST_WEBSITE_REPORT_JSON:-}" || mst_log WARN website WEBSITE_STATE "Website report state could not be persisted"
    mst_render_website_report_text
    mst_log INFO website WEBSITE_REPORT "Website module completed with exit code ${MST_WEBSITE_REPORT_EXIT_CODE}"
    return "${MST_WEBSITE_REPORT_EXIT_CODE}"
}
