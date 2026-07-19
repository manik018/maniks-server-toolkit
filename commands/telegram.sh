#!/usr/bin/env bash
# MST Telegram delivery command.

if [[ -z "${MST_TELEGRAM_COMMAND_LOADED:-}" ]]; then
    readonly MST_TELEGRAM_COMMAND_LOADED=1
    # shellcheck source=delivery/telegram.sh
    source "${MST_DELIVERY_DIR}/telegram.sh"
    # shellcheck source=renderers/telegram_text.sh
    source "${MST_RENDERER_DIR}/telegram_text.sh"
fi

# Send pre-rendered text to Telegram.
mst_command_telegram_run() {
    local message_text

    if [[ "${MST_OUTPUT_MODE}" != "text" ]]; then
        mst_die "${MST_EXIT_USAGE}" "Telegram module supports text output only in v1"
    fi

    message_text="$(mst_telegram_read_cli_message "$@")" || return $?
    mst_telegram_deliver_message "${message_text}"
    mst_render_telegram_result_text
    return "${MST_TELEGRAM_RESULT_EXIT_CODE}"
}
