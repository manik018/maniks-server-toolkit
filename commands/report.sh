#!/usr/bin/env bash
# MST unified report command.

if [[ -z "${MST_REPORT_COMMAND_LOADED:-}" ]]; then
    readonly MST_REPORT_COMMAND_LOADED=1
    # shellcheck source=lib/report.sh
    source "${MST_LIB_DIR}/report.sh"
    # shellcheck source=renderers/report_text.sh
    source "${MST_RENDERER_DIR}/report_text.sh"
fi

# Render a unified terminal report from existing MRRF1 aggregate reports.
mst_command_report_execute() {
    if [[ "${MST_OUTPUT_MODE}" != "text" ]]; then
        mst_die "${MST_EXIT_USAGE}" "Report engine supports text output only in v1"
    fi

    mst_report_collect "$@"
    mst_render_report_text
    return "${MST_REPORT_EXIT_CODE}"
}

mst_command_report_run() {
    mst_command_run_with_lock report mst_command_report_execute "$@"
}
