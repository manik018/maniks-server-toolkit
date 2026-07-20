#!/usr/bin/env bash
# MST unified report command.

if [[ -z "${MST_REPORT_COMMAND_LOADED:-}" ]]; then
    readonly MST_REPORT_COMMAND_LOADED=1
    # shellcheck source=lib/report.sh
    source "${MST_LIB_DIR}/report.sh"
    # shellcheck source=renderers/report_text.sh
    source "${MST_RENDERER_DIR}/report_text.sh"
    # shellcheck source=renderers/report_telegram.sh
    source "${MST_RENDERER_DIR}/report_telegram.sh"
fi

# Render a unified terminal report from existing MRRF1 aggregate reports.
mst_command_report_execute() {
    local style="text"
    local report_args=()
    local arg

    if [[ "${MST_OUTPUT_MODE}" != "text" ]]; then
        mst_die "${MST_EXIT_USAGE}" "Report engine supports text output only in v1"
    fi

    while (($# > 0)); do
        arg="${1}"
        case "${arg}" in
            --style)
                shift || true
                [[ $# -gt 0 ]] || mst_die "${MST_EXIT_USAGE}" "Missing value for --style"
                case "${1}" in
                    text|telegram|digest|critical|auto) style="${1}" ;;
                    *) mst_die "${MST_EXIT_USAGE}" "Unsupported report style: ${1}" ;;
                esac
                ;;
            *=*)
                report_args+=("${arg}")
                ;;
            *)
                mst_die "${MST_EXIT_USAGE}" "Unsupported report option: ${arg}"
                ;;
        esac
        shift || true
    done

    mst_report_collect "${report_args[@]}"
    if [[ "${style}" == "auto" ]]; then
        if [[ "${MST_REPORT_STATUS}" == "critical" ]]; then
            style="critical"
        else
            style="digest"
        fi
    fi

    case "${style}" in
        text) mst_render_report_text ;;
        telegram) mst_render_report_telegram_full ;;
        digest) mst_render_report_telegram_digest ;;
        critical) mst_render_report_telegram_critical ;;
    esac
    return "${MST_REPORT_EXIT_CODE}"
}

mst_command_report_run() {
    mst_command_run_with_lock report mst_command_report_execute "$@"
}
