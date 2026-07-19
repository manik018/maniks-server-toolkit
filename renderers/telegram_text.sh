#!/usr/bin/env bash
# Text renderer for Telegram delivery results.

if [[ -n "${MST_TELEGRAM_RENDERER_LOADED:-}" ]]; then
    return
fi
readonly MST_TELEGRAM_RENDERER_LOADED=1

# Render the sanitized Telegram delivery result.
mst_render_telegram_result_text() {
    mst_header "$(mst_version_string)"
    mst_section "Telegram Delivery"
    mst_table_row "Enabled" "${MST_TELEGRAM_RESULT_ENABLED}"
    mst_table_row "Attempted" "${MST_TELEGRAM_RESULT_ATTEMPTED}"
    mst_table_row "Success" "${MST_TELEGRAM_RESULT_SUCCESS}"
    mst_table_row "Chunks total" "${MST_TELEGRAM_RESULT_CHUNKS_TOTAL}"
    mst_table_row "Chunks sent" "${MST_TELEGRAM_RESULT_CHUNKS_SENT}"
    mst_table_row "HTTP status" "${MST_TELEGRAM_RESULT_HTTP_STATUS:-n/a}"
    mst_table_row "API error code" "${MST_TELEGRAM_RESULT_API_ERROR_CODE:-n/a}"
    mst_table_row "Timestamp" "${MST_TELEGRAM_RESULT_TIMESTAMP}"
    if [[ -n "${MST_TELEGRAM_RESULT_ERROR_DESCRIPTION:-}" ]]; then
        mst_table_row "Result" "${MST_TELEGRAM_RESULT_ERROR_DESCRIPTION}"
    else
        mst_table_row "Result" "Telegram delivery completed."
    fi
}
