#!/usr/bin/env bash
# MST ANSI and text rendering helpers.

# Ensure rendering variables exist before first use.
mst_output_ensure_initialized() {
    if [[ -z "${MST_COLOR_RESET+x}" ]]; then
        mst_output_init
    fi
}

# Initialize the ANSI rendering palette after CLI options are applied.
mst_output_init() {
    if [[ "${MST_COLOR_MODE:-auto}" == "never" ]]; then
        MST_COLOR_RESET=''
        MST_COLOR_RED=''
        MST_COLOR_GREEN=''
        MST_COLOR_YELLOW=''
        MST_COLOR_BLUE=''
        MST_COLOR_BOLD=''
    elif [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
        MST_COLOR_RESET=$'\033[0m'
        MST_COLOR_RED=$'\033[31m'
        MST_COLOR_GREEN=$'\033[32m'
        MST_COLOR_YELLOW=$'\033[33m'
        MST_COLOR_BLUE=$'\033[34m'
        MST_COLOR_BOLD=$'\033[1m'
    else
        MST_COLOR_RESET=''
        MST_COLOR_RED=''
        MST_COLOR_GREEN=''
        MST_COLOR_YELLOW=''
        MST_COLOR_BLUE=''
        MST_COLOR_BOLD=''
    fi

    export MST_COLOR_RESET MST_COLOR_RED MST_COLOR_GREEN MST_COLOR_YELLOW MST_COLOR_BLUE MST_COLOR_BOLD
}

# Print a formatted heading.
mst_header() {
    mst_output_ensure_initialized
    printf '%s%s%s\n' "${MST_COLOR_BOLD}" "$1" "${MST_COLOR_RESET}"
}

# Print a titled section heading.
mst_section() {
    mst_output_ensure_initialized
    printf '\n%s%s%s\n' "${MST_COLOR_BLUE}${MST_COLOR_BOLD}" "$1" "${MST_COLOR_RESET}"
}

# Print an aligned table row.
mst_table_row() {
    local key="$1"
    local value="$2"
    printf '  %-28s %s\n' "${key}" "${value}"
}

# Print a reusable status badge.
mst_status_badge() {
    local status="${1:-INFO}"
    mst_output_ensure_initialized
    case "${status}" in
        INFO) printf '%s[INFO]%s' "${MST_COLOR_BLUE}" "${MST_COLOR_RESET}" ;;
        WARNING) printf '%s[WARN]%s' "${MST_COLOR_YELLOW}" "${MST_COLOR_RESET}" ;;
        ERROR) printf '%s[ERROR]%s' "${MST_COLOR_RED}" "${MST_COLOR_RESET}" ;;
        SUCCESS|OK) printf '%s[OK]%s' "${MST_COLOR_GREEN}" "${MST_COLOR_RESET}" ;;
        *) printf '[%s]' "${status}" ;;
    esac
}

# Print a success block.
mst_success_block() {
    printf '%s %s\n' "$(mst_status_badge SUCCESS)" "$1"
}

# Print a warning block.
mst_warning_block() {
    printf '%s %s\n' "$(mst_status_badge WARNING)" "$1"
}

# Print an error block to stderr.
mst_error_block() {
    printf '%s %s\n' "$(mst_status_badge ERROR)" "$1" >&2
}

# Print an info block.
mst_info_block() {
    if [[ "${MST_QUIET:-0}" -eq 0 ]]; then
        printf '%s %s\n' "$(mst_status_badge INFO)" "$1"
    fi
}
