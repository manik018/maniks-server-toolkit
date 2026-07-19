#!/usr/bin/env bash
# MST WordPress command.

if [[ -z "${MST_WORDPRESS_COMMAND_LOADED:-}" ]]; then
    readonly MST_WORDPRESS_COMMAND_LOADED=1
    # shellcheck source=inspectors/wordpress.sh
    source "${MST_INSPECTOR_DIR}/wordpress.sh"
    # shellcheck source=renderers/wordpress_text.sh
    source "${MST_RENDERER_DIR}/wordpress_text.sh"
fi

# Run the local WordPress monitoring snapshot.
mst_command_wordpress_run() {
    if [[ "${MST_OUTPUT_MODE}" != "text" ]]; then
        mst_die "${MST_EXIT_USAGE}" "WordPress module supports text output only in v1"
    fi

    mst_wordpress_collect_report
    mst_state_save_report wordpress "${MST_WORDPRESS_REPORT_JSON:-}" || mst_log WARN wordpress WORDPRESS_STATE "WordPress report state could not be persisted"
    mst_render_wordpress_report_text
    mst_log INFO wordpress WORDPRESS_REPORT "WordPress module completed with exit code ${MST_WORDPRESS_REPORT_EXIT_CODE}"
    return "${MST_WORDPRESS_REPORT_EXIT_CODE}"
}
