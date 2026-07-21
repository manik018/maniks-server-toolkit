#!/usr/bin/env bash
# MST alert policy command.

if [[ -z "${MST_ALERT_COMMAND_LOADED:-}" ]]; then
    readonly MST_ALERT_COMMAND_LOADED=1
    # shellcheck source=lib/alert.sh
    source "${MST_LIB_DIR}/alert.sh"
    # shellcheck source=renderers/alert_text.sh
    source "${MST_RENDERER_DIR}/alert_text.sh"
fi

# Evaluate existing MRRF1 reports into alert decisions.
mst_command_alert_execute() {
    local update_state="true"
    local confirmed_check="false"
    local args=()

    if [[ "${MST_OUTPUT_MODE}" != "text" ]]; then
        mst_die "${MST_EXIT_USAGE}" "Alert engine supports text output only in v1"
    fi

    while (($# > 0)); do
        case "${1}" in
            --has-confirmed-active-issue)
                confirmed_check="true"
                ;;
            --no-state)
                update_state="false"
                ;;
            *=*)
                args+=("${1}")
                ;;
            *)
                mst_die "${MST_EXIT_USAGE}" "Unsupported alert option: ${1}"
                ;;
        esac
        shift || true
    done

    if [[ "${confirmed_check}" == "true" ]]; then
        [[ "${#args[@]}" -eq 0 ]] || mst_die "${MST_EXIT_USAGE}" "Confirmed alert check does not accept report inputs"
        mst_alert_has_confirmed_active_issue
        return $?
    fi

    mst_alert_evaluate "${update_state}" "${args[@]}"
    mst_render_alert_report_text
    return "${MST_ALERT_EXIT_CODE}"
}

mst_command_alert_run() {
    mst_command_run_with_lock alert mst_command_alert_execute "$@"
}
