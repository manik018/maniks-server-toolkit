#!/usr/bin/env bash
# MST backup command.

if [[ -z "${MST_BACKUP_COMMAND_LOADED:-}" ]]; then
    readonly MST_BACKUP_COMMAND_LOADED=1
    # shellcheck source=inspectors/backup.sh
    source "${MST_INSPECTOR_DIR}/backup.sh"
    # shellcheck source=renderers/backup_text.sh
    source "${MST_RENDERER_DIR}/backup_text.sh"
fi

# Run the local backup monitoring snapshot.
mst_command_backup_run() {
    if [[ "${MST_OUTPUT_MODE}" != "text" ]]; then
        mst_die "${MST_EXIT_USAGE}" "Backup module supports text output only in v1"
    fi

    mst_backup_collect_report
    mst_render_backup_report_text
    mst_log INFO backup BACKUP_REPORT "Backup module completed with exit code ${MST_BACKUP_REPORT_EXIT_CODE}"
    return "${MST_BACKUP_REPORT_EXIT_CODE}"
}
