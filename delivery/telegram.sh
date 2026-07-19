#!/usr/bin/env bash
# Telegram delivery adapter for pre-rendered text.

if [[ -n "${MST_TELEGRAM_DELIVERY_LOADED:-}" ]]; then
    return
fi
readonly MST_TELEGRAM_DELIVERY_LOADED=1

readonly MST_TELEGRAM_MAX_CHARS_DEFAULT=3900
readonly MST_TELEGRAM_RETRY_AFTER_CAP_SECONDS=30

# Normalize one boolean-like config value for Telegram form fields.
mst_telegram_bool() {
    case "${1:-}" in
        1|yes|true) printf 'true' ;;
        *) printf 'false' ;;
    esac
}

# Return a timestamp for delivery result metadata.
mst_telegram_now_utc() {
    mst_mrrf_now_utc
}

# Redact sensitive values from diagnostics.
mst_telegram_redact() {
    local value="${1:-}"
    if [[ -n "${MST_TELEGRAM_BOT_TOKEN:-}" ]]; then
        value="${value//${MST_TELEGRAM_BOT_TOKEN}/[REDACTED]}"
    fi
    printf '%s' "${value}"
}

# Initialize the result object exposed to the command renderer.
mst_telegram_result_init() {
    export MST_TELEGRAM_RESULT_ENABLED="$(mst_telegram_bool "${MST_TELEGRAM_ENABLED:-false}")"
    export MST_TELEGRAM_RESULT_ATTEMPTED="false"
    export MST_TELEGRAM_RESULT_SUCCESS="false"
    export MST_TELEGRAM_RESULT_CHUNKS_TOTAL="0"
    export MST_TELEGRAM_RESULT_CHUNKS_SENT="0"
    export MST_TELEGRAM_RESULT_HTTP_STATUS=""
    export MST_TELEGRAM_RESULT_API_ERROR_CODE=""
    export MST_TELEGRAM_RESULT_ERROR_DESCRIPTION=""
    export MST_TELEGRAM_RESULT_TIMESTAMP="$(mst_telegram_now_utc)"
    export MST_TELEGRAM_RESULT_EXIT_CODE="${MST_EXIT_OK}"
}

# Mark a sanitized delivery failure.
mst_telegram_result_failure() {
    local exit_code="${1:?exit code required}"
    local description="${2:?description required}"
    local http_status="${3:-}"
    local api_error_code="${4:-}"

    export MST_TELEGRAM_RESULT_SUCCESS="false"
    export MST_TELEGRAM_RESULT_HTTP_STATUS="${http_status}"
    export MST_TELEGRAM_RESULT_API_ERROR_CODE="${api_error_code}"
    export MST_TELEGRAM_RESULT_ERROR_DESCRIPTION="$(mst_telegram_redact "$(mst_mrrf_sanitize_text "${description}" 200)")"
    export MST_TELEGRAM_RESULT_EXIT_CODE="${exit_code}"
}

# Return success if one input path is a symlink.
mst_telegram_input_is_symlink() {
    [[ -L "${1:-}" ]]
}

# Validate one read-only input file and print its canonical path.
mst_telegram_validate_input_file() {
    local file_path="${1:?file path required}"
    local canonical_path parent_path owner_uid mode parent_owner parent_mode

    [[ "${file_path}" == /* ]] || return 1
    ! mst_telegram_input_is_symlink "${file_path}" || return 1
    mst_fs_is_regular_file "${file_path}" || return 1
    canonical_path="$(mst_fs_canonical_path "${file_path}")" || return 1
    [[ "${canonical_path}" == "${file_path}" ]] || return 1
    [[ -r "${canonical_path}" ]] || return 1

    owner_uid="$(mst_fs_path_owner_uid "${canonical_path}")" || return 1
    mst_fs_is_safe_owner_uid "${owner_uid}" || return 1
    mode="$(mst_fs_path_mode_octal "${canonical_path}")" || return 1
    mst_fs_is_group_or_other_writable "${mode}" && return 1

    parent_path="$(dirname -- "${canonical_path}")"
    mst_fs_is_directory "${parent_path}" || return 1
    parent_owner="$(mst_fs_path_owner_uid "${parent_path}")" || return 1
    mst_fs_is_safe_owner_uid "${parent_owner}" || return 1
    parent_mode="$(mst_fs_path_mode_octal "${parent_path}")" || return 1
    mst_fs_is_group_or_other_writable "${parent_mode}" && return 1

    printf '%s' "${canonical_path}"
}

# Read a CLI message from stdin or a validated --file path.
mst_telegram_read_cli_message() {
    local input_file="" arg

    while (($# > 0)); do
        arg="${1}"
        case "${arg}" in
            --file)
                shift || true
                [[ $# -gt 0 ]] || mst_die "${MST_EXIT_USAGE}" "Missing value for --file"
                input_file="${1}"
                ;;
            *)
                mst_die "${MST_EXIT_USAGE}" "Unsupported Telegram option: ${arg}"
                ;;
        esac
        shift || true
    done

    if [[ -n "${input_file}" ]]; then
        input_file="$(mst_telegram_validate_input_file "${input_file}")" || mst_die "${MST_EXIT_SECURITY}" "Unsafe Telegram input file"
        printf '%s' "$(< "${input_file}")"
    else
        local message=""
        while IFS= read -r line || [[ -n "${line}" ]]; do
            if [[ -n "${message}" ]]; then
                message+=$'\n'
            fi
            message+="${line}"
        done
        printf '%s' "${message}"
    fi
}

# Split one message into deterministic Telegram-safe chunks.
mst_telegram_split_message() {
    local message_text="${1-}"
    local max_chars="${2:-${MST_TELEGRAM_MAX_CHARS_DEFAULT}}"
    local remaining chunk window split_at index

    declare -ga MST_TELEGRAM_CHUNKS=()
    [[ "${max_chars}" =~ ^[0-9]+$ ]] && (( max_chars > 0 )) || max_chars="${MST_TELEGRAM_MAX_CHARS_DEFAULT}"

    remaining="${message_text}"
    while ((${#remaining} > max_chars)); do
        window="${remaining:0:max_chars}"
        split_at=0
        for (( index = ${#window} - 1; index >= 0; index-- )); do
            if [[ "${window:index:1}" == $'\n' ]]; then
                split_at=$(( index + 1 ))
                break
            fi
        done
        (( split_at > 0 )) || split_at="${max_chars}"
        chunk="${remaining:0:split_at}"
        MST_TELEGRAM_CHUNKS+=("${chunk}")
        remaining="${remaining:split_at}"
    done
    MST_TELEGRAM_CHUNKS+=("${remaining}")
}

# Send one chunk using curl and print http_status|body.
mst_telegram_curl_send() {
    local chunk_text="${1:?chunk required}"
    local api_url="https://api.telegram.org/bot${MST_TELEGRAM_BOT_TOKEN}/sendMessage"
    local response http_status body
    local -a curl_args=(
        -sS
        --connect-timeout "${MST_TELEGRAM_TIMEOUT_SECONDS}"
        --max-time "${MST_TELEGRAM_TIMEOUT_SECONDS}"
        -w $'\n%{http_code}'
        -X POST
        -F "chat_id=${MST_TELEGRAM_CHAT_ID}"
        -F "text=${chunk_text}"
        -F "disable_web_page_preview=$(mst_telegram_bool "${MST_TELEGRAM_DISABLE_WEB_PAGE_PREVIEW}")"
    )

    if [[ -n "${MST_TELEGRAM_PARSE_MODE:-}" ]]; then
        curl_args+=( -F "parse_mode=${MST_TELEGRAM_PARSE_MODE}" )
    fi

    response="$(printf 'url = "%s"\n' "${api_url}" | curl "${curl_args[@]}" --config -)" || return $?
    http_status="${response##*$'\n'}"
    body="${response%$'\n'*}"
    printf '%s|%s' "${http_status}" "${body}"
}

# Extract a simple Telegram JSON boolean field.
mst_telegram_json_bool_field() {
    local json_payload="${1:-}"
    local field_name="${2:?field required}"
    sed -n "s/.*\"${field_name}\"[[:space:]]*:[[:space:]]*\\(true\\|false\\).*/\\1/p" <<< "${json_payload}" | head -n 1
}

# Extract a simple Telegram JSON string field.
mst_telegram_json_string_field() {
    local json_payload="${1:-}"
    local field_name="${2:?field required}"
    sed -n "s/.*\"${field_name}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" <<< "${json_payload}" | head -n 1
}

# Extract a simple Telegram JSON number field.
mst_telegram_json_number_field() {
    local json_payload="${1:-}"
    local field_name="${2:?field required}"
    sed -n "s/.*\"${field_name}\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" <<< "${json_payload}" | head -n 1
}

# Return a bounded retry_after delay from one API body.
mst_telegram_retry_after_seconds() {
    local body="${1:-}"
    local retry_after
    retry_after="$(mst_telegram_json_number_field "${body}" "retry_after")"
    if [[ "${retry_after}" =~ ^[0-9]+$ ]]; then
        if (( retry_after > MST_TELEGRAM_RETRY_AFTER_CAP_SECONDS )); then
            printf '%s' "${MST_TELEGRAM_RETRY_AFTER_CAP_SECONDS}"
        else
            printf '%s' "${retry_after}"
        fi
    else
        printf '%s' "${MST_TELEGRAM_RETRY_DELAY_SECONDS}"
    fi
}

# Return success if a failed attempt is safe to retry.
mst_telegram_should_retry() {
    local curl_exit="${1:?curl exit required}"
    local http_status="${2:-}"

    if [[ "${curl_exit}" -ne 0 ]]; then
        return 0
    fi
    [[ "${http_status}" == "429" ]] && return 0
    [[ "${http_status}" =~ ^5[0-9][0-9]$ ]] && return 0
    return 1
}

# Send one chunk with bounded retries.
mst_telegram_send_chunk() {
    local chunk_text="${1:?chunk required}"
    local attempt=0 max_attempts response curl_exit http_status body api_ok api_code api_description delay_seconds

    max_attempts=$(( MST_TELEGRAM_MAX_RETRIES + 1 ))
    while (( attempt < max_attempts )); do
        attempt=$(( attempt + 1 ))
        response=""
        curl_exit=0
        response="$(mst_telegram_curl_send "${chunk_text}" 2>&1)" || curl_exit=$?
        if [[ "${curl_exit}" -eq 0 ]]; then
            http_status="${response%%|*}"
            body="${response#*|}"
            export MST_TELEGRAM_RESULT_HTTP_STATUS="${http_status}"
            api_ok="$(mst_telegram_json_bool_field "${body}" "ok")"
            if [[ "${http_status}" =~ ^2[0-9][0-9]$ ]] && [[ "${api_ok}" == "true" ]]; then
                return 0
            fi
            api_code="$(mst_telegram_json_number_field "${body}" "error_code")"
            api_description="$(mst_telegram_json_string_field "${body}" "description")"
            if [[ -z "${api_ok}" ]] && [[ "${http_status}" =~ ^2[0-9][0-9]$ ]]; then
                mst_telegram_result_failure "${MST_EXIT_INTERNAL}" "Malformed Telegram API response" "${http_status}" ""
                return 1
            fi
            if [[ "${api_ok}" == "false" ]]; then
                mst_telegram_result_failure "${MST_EXIT_NETWORK}" "Telegram API rejected the request: ${api_description:-request failed}" "${http_status}" "${api_code:-}"
            else
                mst_telegram_result_failure "${MST_EXIT_NETWORK}" "Telegram delivery failed with HTTP ${http_status}" "${http_status}" "${api_code:-}"
            fi
        else
            http_status=""
            body=""
            mst_telegram_result_failure "${MST_EXIT_NETWORK}" "Telegram network delivery failed" "" ""
        fi

        if (( attempt < max_attempts )) && mst_telegram_should_retry "${curl_exit}" "${http_status}"; then
            delay_seconds="${MST_TELEGRAM_RETRY_DELAY_SECONDS}"
            if [[ "${http_status}" == "429" ]]; then
                delay_seconds="$(mst_telegram_retry_after_seconds "${body}")"
            fi
            sleep "${delay_seconds}"
            continue
        fi
        return 1
    done
    return 1
}

# Deliver one pre-rendered message to Telegram.
mst_telegram_deliver_message() {
    local message_text="${1-}"
    local chunk chunk_total

    mst_telegram_result_init
    if [[ "$(mst_telegram_bool "${MST_TELEGRAM_ENABLED:-false}")" != "true" ]]; then
        export MST_TELEGRAM_RESULT_ERROR_DESCRIPTION="Telegram delivery is disabled."
        return 0
    fi

    if [[ -z "${MST_TELEGRAM_BOT_TOKEN:-}" ]]; then
        mst_telegram_result_failure "${MST_EXIT_USAGE}" "Telegram bot token is not configured" "" ""
        return 0
    fi
    if [[ -z "${MST_TELEGRAM_CHAT_ID:-}" ]]; then
        mst_telegram_result_failure "${MST_EXIT_USAGE}" "Telegram chat ID is not configured" "" ""
        return 0
    fi
    if ! mst_command_exists curl; then
        mst_telegram_result_failure "${MST_EXIT_DEPENDENCY}" "curl is unavailable for Telegram delivery" "" ""
        return 0
    fi
    if [[ -z "${message_text}" ]]; then
        mst_telegram_result_failure "${MST_EXIT_USAGE}" "Telegram message is empty" "" ""
        return 0
    fi

    export MST_TELEGRAM_RESULT_ATTEMPTED="true"
    mst_telegram_split_message "${message_text}" "${MST_TELEGRAM_MAX_CHARS:-${MST_TELEGRAM_MAX_CHARS_DEFAULT}}"
    chunk_total="${#MST_TELEGRAM_CHUNKS[@]}"
    export MST_TELEGRAM_RESULT_CHUNKS_TOTAL="${chunk_total}"
    mst_log INFO telegram TELEGRAM_DELIVERY_STARTED "Telegram delivery started with ${chunk_total} chunks"

    for chunk in "${MST_TELEGRAM_CHUNKS[@]}"; do
        if mst_telegram_send_chunk "${chunk}"; then
            export MST_TELEGRAM_RESULT_CHUNKS_SENT="$(( MST_TELEGRAM_RESULT_CHUNKS_SENT + 1 ))"
            mst_log INFO telegram TELEGRAM_CHUNK_SENT "Telegram chunk ${MST_TELEGRAM_RESULT_CHUNKS_SENT} of ${chunk_total} sent"
        else
            mst_log WARNING telegram TELEGRAM_DELIVERY_FAILED "Telegram delivery failed with HTTP ${MST_TELEGRAM_RESULT_HTTP_STATUS:-unknown}"
            return 0
        fi
    done

    export MST_TELEGRAM_RESULT_SUCCESS="true"
    export MST_TELEGRAM_RESULT_ERROR_DESCRIPTION=""
    export MST_TELEGRAM_RESULT_EXIT_CODE="${MST_EXIT_OK}"
    mst_log INFO telegram TELEGRAM_DELIVERY_COMPLETE "Telegram delivery completed"
}
