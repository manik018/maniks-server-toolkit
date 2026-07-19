#!/usr/bin/env bash
# MST structured logging framework.

# Initialize the local log sink if a writable location exists.
mst_logging_init() {
    export MST_LOG_LEVEL="${MST_LOG_LEVEL:-INFO}"
    export MST_LOG_DIR="${MST_LOG_DIR:-/var/log/mst}"
    export MST_STATE_DIR="${MST_STATE_DIR:-/var/lib/mst}"
    export MST_LOCK_DIR="${MST_LOCK_DIR:-${MST_STATE_DIR}/locks}"
    unset MST_LOG_FILE
    export MST_LOG_WRITABLE=0

    if mst_fs_validate_runtime_write_paths; then
        if [[ -d "${MST_LOG_DIR}" ]] && [[ -w "${MST_LOG_DIR}" ]]; then
            if [[ ! -e "${MST_LOG_FILE}" ]] || [[ -w "${MST_LOG_FILE}" ]]; then
                MST_LOG_WRITABLE=1
            fi
        fi
    fi
    export MST_LOG_WRITABLE
}

# Sanitize a log message before persistence.
mst_log_sanitize_message() {
    local message="$*"
    message="${message//$'\n'/ }"
    message="${message//$'\r'/ }"
    message="${message//$'\t'/ }"
    message="${message//  / }"
    printf '%s' "${message}"
}

# Return success if the requested log level should be written.
mst_should_log_level() {
    local requested="${1:-INFO}"
    local current="${MST_LOG_LEVEL:-INFO}"
    local requested_rank=0
    local current_rank=0

    case "${requested}" in
        DEBUG) requested_rank=10 ;;
        INFO) requested_rank=20 ;;
        WARNING) requested_rank=30 ;;
        ERROR) requested_rank=40 ;;
    esac
    case "${current}" in
        DEBUG) current_rank=10 ;;
        INFO) current_rank=20 ;;
        WARNING) current_rank=30 ;;
        ERROR) current_rank=40 ;;
    esac
    (( requested_rank >= current_rank ))
}

# Write a structured log event if the sink is available.
mst_log() {
    local level="${1:?level required}"
    local component="${2:?component required}"
    local event_code="${3:?event code required}"
    shift 3 || true
    local message

    mst_should_log_level "${level}" || return 0
    message="$(mst_log_sanitize_message "$*")"
    [[ "${MST_LOG_WRITABLE:-0}" -eq 1 ]] || return 0

    printf '%s level=%s component=%s event=%s message="%s"\n' \
        "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        "${level}" \
        "${component}" \
        "${event_code}" \
        "${message}" >> "${MST_LOG_FILE}"
}
