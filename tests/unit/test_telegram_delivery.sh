#!/usr/bin/env bash
# Validate Telegram delivery behavior without calling the real API.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/telegram"
SAFE_DIR="${TMP_DIR}/safe"
CALL_FILE="${TMP_DIR}/calls.log"
TEXT_FILE="${TMP_DIR}/texts.log"
mkdir -p "${SAFE_DIR}"
chmod 0700 "${TMP_DIR}" "${SAFE_DIR}"

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/delivery/telegram.sh"
source "${ROOT_DIR}/renderers/telegram_text.sh"

mst_fs_validate_runtime_write_paths() {
    return 0
}

reset_telegram_config() {
    export MST_TELEGRAM_ENABLED="true"
    export MST_TELEGRAM_BOT_TOKEN="123456:SECRET_TOKEN"
    export MST_TELEGRAM_CHAT_ID="123456789"
    export MST_TELEGRAM_PARSE_MODE=""
    export MST_TELEGRAM_DISABLE_WEB_PAGE_PREVIEW="true"
    export MST_TELEGRAM_TIMEOUT_SECONDS="15"
    export MST_TELEGRAM_MAX_RETRIES="2"
    export MST_TELEGRAM_RETRY_DELAY_SECONDS="0"
    export MST_TELEGRAM_MAX_CHARS="20"
    export MST_LOG_WRITABLE=0
    : > "${CALL_FILE}"
    : > "${TEXT_FILE}"
    rm -f "${TMP_DIR}"/chunk_*.txt
    TELEGRAM_RESPONSES=()
}

declare -ga TELEGRAM_RESPONSES=()

telegram_call_count() {
    wc -l < "${CALL_FILE}" | tr -d ' '
}

telegram_sent_joined() {
    local chunk_file
    for chunk_file in "${TMP_DIR}"/chunk_*.txt; do
        [[ -e "${chunk_file}" ]] || continue
        cat "${chunk_file}"
    done
}

telegram_sent_line() {
    local line_number="${1:?line required}"
    cat "${TMP_DIR}/chunk_${line_number}.txt"
}

mst_command_exists() {
    [[ "${1}" == "curl" ]]
}

sleep() {
    return 0
}

reset_telegram_config
MST_TELEGRAM_PARSE_MODE="HTML"
curl() {
    printf '%s\n' "$*" > "${TMP_DIR}/curl-argv.txt"
    cat > "${TMP_DIR}/curl-config.txt"
    printf '%s\n%s' '{"ok":true,"result":{"message_id":1}}' '200'
}
mst_telegram_curl_send "argv check" > "${TMP_DIR}/curl-result.txt"
curl_argv="$(cat "${TMP_DIR}/curl-argv.txt")"
curl_config="$(cat "${TMP_DIR}/curl-config.txt")"
curl_result="$(cat "${TMP_DIR}/curl-result.txt")"
[[ "${curl_argv}" != *"123456:SECRET_TOKEN"* ]] || exit 1
[[ "${curl_argv}" == *"--config -"* ]] || exit 1
[[ "${curl_config}" == 'url = "https://api.telegram.org/bot123456:SECRET_TOKEN/sendMessage"' ]] || exit 1
[[ "${curl_result}" == '200|{"ok":true,"result":{"message_id":1}}' ]] || exit 1
[[ "${curl_argv}" == *"-F chat_id=123456789"* ]] || exit 1
[[ "${curl_argv}" == *"-F text=argv check"* ]] || exit 1
[[ "${curl_argv}" == *"-F disable_web_page_preview=true"* ]] || exit 1
[[ "${curl_argv}" == *"-F parse_mode=HTML"* ]] || exit 1
rm -f -- "${TMP_DIR}/curl-config.txt"
if grep -R '123456:SECRET_TOKEN' "${TMP_DIR}" >/dev/null 2>&1; then
    printf 'Telegram token should not remain in temporary files.\n' >&2
    exit 1
fi
unset -f curl

mst_telegram_curl_send_mock() {
    local chunk_text="${1:?chunk required}"
    local index
    index="$(telegram_call_count)"
    printf 'call\n' >> "${CALL_FILE}"
    printf '%s' "${chunk_text}" > "${TMP_DIR}/chunk_$(( index + 1 )).txt"
    if [[ "${#TELEGRAM_RESPONSES[@]}" -gt "${index}" ]]; then
        printf '%s' "${TELEGRAM_RESPONSES[$index]}"
    else
        printf '%s' '200|{"ok":true,"result":{"message_id":1}}'
    fi
}

mst_telegram_curl_send() {
    mst_telegram_curl_send_mock "$@"
}

reset_telegram_config
MST_TELEGRAM_ENABLED="false"
mst_telegram_deliver_message "hello"
[[ "${MST_TELEGRAM_RESULT_ENABLED}" == "false" ]] || exit 1
[[ "${MST_TELEGRAM_RESULT_ATTEMPTED}" == "false" ]] || exit 1
[[ "${MST_TELEGRAM_RESULT_EXIT_CODE}" == "0" ]] || exit 1

reset_telegram_config
mst_telegram_deliver_message "hello"
[[ "${MST_TELEGRAM_RESULT_SUCCESS}" == "true" ]] || exit 1
[[ "${MST_TELEGRAM_RESULT_CHUNKS_TOTAL}" == "1" ]] || exit 1
[[ "${MST_TELEGRAM_RESULT_CHUNKS_SENT}" == "1" ]] || exit 1
[[ "$(telegram_sent_line 1)" == "hello" ]] || exit 1

reset_telegram_config
message=$'alpha\nbeta line that is longer\ngamma'
mst_telegram_deliver_message "${message}"
rejoined="$(telegram_sent_joined)"
[[ "${rejoined}" == "${message}" ]] || exit 1
[[ "$(telegram_call_count)" -gt 1 ]] || exit 1
[[ "$(tail -c 1 "${TMP_DIR}/chunk_1.txt" | od -An -t u1 | tr -d ' ')" == "10" ]] || exit 1

reset_telegram_config
long_line="abcdefghijklmnopqrstuvwxyz0123456789"
mst_telegram_deliver_message "${long_line}"
rejoined="$(telegram_sent_joined)"
[[ "${rejoined}" == "${long_line}" ]] || exit 1
[[ "$(telegram_call_count)" -eq 2 ]] || exit 1

reset_telegram_config
mst_telegram_deliver_message ""
[[ "${MST_TELEGRAM_RESULT_SUCCESS}" == "false" ]] || exit 1
[[ "${MST_TELEGRAM_RESULT_EXIT_CODE}" == "${MST_EXIT_USAGE}" ]] || exit 1

reset_telegram_config
MST_TELEGRAM_BOT_TOKEN=""
mst_telegram_deliver_message "hello"
[[ "${MST_TELEGRAM_RESULT_EXIT_CODE}" == "${MST_EXIT_USAGE}" ]] || exit 1

if (
    mst_config_apply_defaults
    reset_telegram_config
    MST_TELEGRAM_BOT_TOKEN=""
    mst_config_validate
) >/dev/null 2>&1; then
    printf 'enabled Telegram config without token should be rejected.\n' >&2
    exit 1
fi

reset_telegram_config
MST_TELEGRAM_CHAT_ID=""
mst_telegram_deliver_message "hello"
[[ "${MST_TELEGRAM_RESULT_EXIT_CODE}" == "${MST_EXIT_USAGE}" ]] || exit 1

if (
    mst_config_apply_defaults
    reset_telegram_config
    MST_TELEGRAM_CHAT_ID=""
    mst_config_validate
) >/dev/null 2>&1; then
    printf 'enabled Telegram config without chat ID should be rejected.\n' >&2
    exit 1
fi

reset_telegram_config
mst_command_exists() {
    return 1
}
mst_telegram_deliver_message "hello"
[[ "${MST_TELEGRAM_RESULT_EXIT_CODE}" == "${MST_EXIT_DEPENDENCY}" ]] || exit 1
mst_command_exists() {
    [[ "${1}" == "curl" ]]
}

reset_telegram_config
TELEGRAM_RESPONSES=('429|{"ok":false,"error_code":429,"description":"Too Many Requests","parameters":{"retry_after":1}}' '200|{"ok":true}')
mst_telegram_deliver_message "hello"
[[ "${MST_TELEGRAM_RESULT_SUCCESS}" == "true" ]] || exit 1
[[ "$(telegram_call_count)" -eq 2 ]] || exit 1

reset_telegram_config
TELEGRAM_RESPONSES=('500|{"ok":false,"error_code":500,"description":"Server error"}' '200|{"ok":true}')
mst_telegram_deliver_message "hello"
[[ "${MST_TELEGRAM_RESULT_SUCCESS}" == "true" ]] || exit 1
[[ "$(telegram_call_count)" -eq 2 ]] || exit 1

reset_telegram_config
TELEGRAM_RESPONSES=('400|{"ok":false,"error_code":400,"description":"Bad Request: chat not found"}')
mst_telegram_deliver_message "hello"
[[ "${MST_TELEGRAM_RESULT_SUCCESS}" == "false" ]] || exit 1
[[ "$(telegram_call_count)" -eq 1 ]] || exit 1
[[ "${MST_TELEGRAM_RESULT_API_ERROR_CODE}" == "400" ]] || exit 1

reset_telegram_config
TELEGRAM_RESPONSES=('200|{"ok":false,"error_code":401,"description":"Unauthorized"}')
mst_telegram_deliver_message "hello"
[[ "${MST_TELEGRAM_RESULT_SUCCESS}" == "false" ]] || exit 1
[[ "${MST_TELEGRAM_RESULT_API_ERROR_CODE}" == "401" ]] || exit 1

reset_telegram_config
TELEGRAM_RESPONSES=('200|not-json')
mst_telegram_deliver_message "hello"
[[ "${MST_TELEGRAM_RESULT_EXIT_CODE}" == "${MST_EXIT_INTERNAL}" ]] || exit 1

reset_telegram_config
TELEGRAM_RESPONSES=('200|{"ok":true}' '400|{"ok":false,"error_code":400,"description":"Bad Request"}')
MST_TELEGRAM_MAX_CHARS="5"
mst_telegram_deliver_message "hello-world"
[[ "${MST_TELEGRAM_RESULT_SUCCESS}" == "false" ]] || exit 1
[[ "${MST_TELEGRAM_RESULT_CHUNKS_SENT}" == "1" ]] || exit 1

reset_telegram_config
TELEGRAM_RESPONSES=('500|{"ok":false,"error_code":500,"description":"Server error"}' '500|{"ok":false,"error_code":500,"description":"Server error"}' '500|{"ok":false,"error_code":500,"description":"Server error"}')
mst_telegram_deliver_message "hello"
[[ "$(telegram_call_count)" -eq 3 ]] || exit 1
[[ "${MST_TELEGRAM_RESULT_SUCCESS}" == "false" ]] || exit 1

reset_telegram_config
TELEGRAM_RESPONSES=('400|{"ok":false,"error_code":400,"description":"123456:SECRET_TOKEN"}')
mst_telegram_deliver_message "hello"
rendered="$(mst_render_telegram_result_text)"
[[ "${MST_TELEGRAM_RESULT_ERROR_DESCRIPTION}" != *"123456:SECRET_TOKEN"* ]] || exit 1
[[ "${rendered}" != *"123456:SECRET_TOKEN"* ]] || exit 1

reset_telegram_config
safe_file="${SAFE_DIR}/message.txt"
printf 'from file' > "${safe_file}"
chmod 0600 "${safe_file}"
read_file_message="$(mst_telegram_read_cli_message --file "${safe_file}")"
[[ "${read_file_message}" == "from file" ]] || exit 1

symlink_file="${SAFE_DIR}/message-link.txt"
printf 'fake symlink target' > "${symlink_file}"
mst_telegram_input_is_symlink() {
    [[ "${1}" == "${symlink_file}" ]]
}
if mst_telegram_validate_input_file "${symlink_file}" >/dev/null 2>&1; then
    printf 'symlink input should be rejected.\n' >&2
    exit 1
fi
mst_telegram_input_is_symlink() {
    [[ -L "${1:-}" ]]
}

mst_health_collect_report() {
    printf 'monitoring collector should not be called.\n' >&2
    exit 1
}

mst_report_collect() {
    printf 'report engine should not be called.\n' >&2
    exit 1
}

reset_telegram_config
mst_telegram_deliver_message "delivery only"
[[ "${MST_TELEGRAM_RESULT_SUCCESS}" == "true" ]] || exit 1

printf 'test_telegram_delivery.sh passed.\n'
