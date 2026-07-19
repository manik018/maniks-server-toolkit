#!/usr/bin/env bash
# MST foundation uninstaller.
set -euo pipefail
umask 027

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="${BIN_DIR:-${PREFIX}/bin}"
LIB_DIR="${LIB_DIR:-${PREFIX}/lib/mst}"
CONFIG_DIR="${CONFIG_DIR:-/etc/mst}"
LOG_DIR="${LOG_DIR:-/var/log/mst}"
STATE_DIR="${STATE_DIR:-/var/lib/mst}"
LOGROTATE_FILE="${LOGROTATE_FILE:-/etc/logrotate.d/mst}"
CRON_TEMPLATE_FILE="${CRON_TEMPLATE_FILE:-${CONFIG_DIR}/mst.cron.example}"

DRY_RUN=0
VERBOSE=0
REMOVE_CONFIG=0

uninstall_log() {
    if [[ "${VERBOSE}" -eq 1 ]]; then
        printf '%s\n' "$*"
    fi
}

run_cmd() {
    uninstall_log "RUN: $*"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        return 0
    fi
    "$@"
}

parse_args() {
    while (($# > 0)); do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --verbose) VERBOSE=1 ;;
            --remove-config) REMOVE_CONFIG=1 ;;
            *)
                printf 'Unknown uninstaller option: %s\n' "$1" >&2
                exit 2
                ;;
        esac
        shift
    done
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        printf 'uninstall.sh must be run as root.\n' >&2
        exit 4
    fi
}

assert_target() {
    case "${1:?path required}" in
        /usr/local/bin/mst|/usr/local/lib/mst|/usr/local/lib/mst/*|/etc/mst|/etc/mst/*|/var/log/mst|/var/log/mst/*|/var/lib/mst|/var/lib/mst/*|/etc/logrotate.d/mst)
            ;;
        *)
            printf 'Unsafe uninstaller target: %s\n' "${1}" >&2
            exit 8
            ;;
    esac
}

safe_remove_file() {
    local target="${1:?target required}"
    assert_target "${target}"
    [[ ! -L "${target}" ]] || {
        printf 'Refusing to remove symlink: %s\n' "${target}" >&2
        exit 8
    }
    if [[ -e "${target}" ]]; then
        run_cmd rm -f -- "${target}"
    fi
}

safe_remove_dir() {
    local target="${1:?target required}"
    assert_target "${target}"
    [[ ! -L "${target}" ]] || {
        printf 'Refusing to remove symlink: %s\n' "${target}" >&2
        exit 8
    }
    if [[ -d "${target}" ]]; then
        run_cmd rm -rf -- "${target}"
    fi
}

main() {
    parse_args "$@"
    require_root

    safe_remove_file "${BIN_DIR}/mst"
    safe_remove_dir "${LIB_DIR}"
    safe_remove_file "${LOGROTATE_FILE}"
    safe_remove_file "${CRON_TEMPLATE_FILE}"

    if [[ "${REMOVE_CONFIG}" -eq 1 ]]; then
        safe_remove_dir "${CONFIG_DIR}"
        safe_remove_dir "${LOG_DIR}"
        safe_remove_dir "${STATE_DIR}"
    else
        printf 'Configuration preserved. Use --remove-config to remove MST-owned config and state.\n'
    fi

    printf 'MST foundation uninstallation complete.\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
