#!/usr/bin/env bash
# MST exit code framework and centralized error handling.

readonly MST_EXIT_OK=0
readonly MST_EXIT_INTERNAL=1
readonly MST_EXIT_USAGE=2
readonly MST_EXIT_DEPENDENCY=3
readonly MST_EXIT_PERMISSION=4
readonly MST_EXIT_TIMEOUT=5
readonly MST_EXIT_NETWORK=6
readonly MST_EXIT_PARTIAL=7
readonly MST_EXIT_SECURITY=8

# Exit immediately with a formatted error.
mst_die() {
    local code="${1:?exit code required}"
    shift || true
    mst_error_block "$*"
    exit "${code}"
}

# Return the canonical exit code for a known error category.
mst_exit_code_for_category() {
    local category="${1:-internal}"
    case "${category}" in
        warning) printf '%s' "${MST_EXIT_PARTIAL}" ;;
        critical|internal|unknown) printf '%s' "${MST_EXIT_INTERNAL}" ;;
        permission) printf '%s' "${MST_EXIT_PERMISSION}" ;;
        timeout) printf '%s' "${MST_EXIT_TIMEOUT}" ;;
        network) printf '%s' "${MST_EXIT_NETWORK}" ;;
        configuration) printf '%s' "${MST_EXIT_USAGE}" ;;
        dependency) printf '%s' "${MST_EXIT_DEPENDENCY}" ;;
        *) printf '%s' "${MST_EXIT_INTERNAL}" ;;
    esac
}

# Return a foundation-phase not implemented response.
mst_not_implemented() {
    printf 'NOT IMPLEMENTED\n'
    return "${MST_EXIT_INTERNAL}"
}
