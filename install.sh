#!/usr/bin/env bash
# MST foundation installer.
set -euo pipefail
umask 027

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

reject_install_path_overrides() {
    local name value
    for name in PREFIX BIN_DIR LIB_DIR CONFIG_DIR LOG_DIR STATE_DIR LOCK_DIR LOGROTATE_FILE CRON_TEMPLATE_FILE; do
        value="${!name-}"
        if [[ -n "${value}" ]]; then
            printf 'Custom install paths are unsupported; unset %s and use the canonical MST paths.\n' "${name}" >&2
            exit 2
        fi
    done
}

reject_install_path_overrides

PREFIX="/usr/local"
BIN_DIR="/usr/local/bin"
LIB_DIR="/usr/local/lib/mst"
CONFIG_DIR="/etc/mst"
LOG_DIR="/var/log/mst"
STATE_DIR="/var/lib/mst"
LOCK_DIR="/var/lib/mst/locks"
RUNTIME_WRITE_GROUP="sudo"
LOGROTATE_FILE="/etc/logrotate.d/mst"
CRON_TEMPLATE_FILE="/etc/mst/mst.cron.example"

DRY_RUN=0
VERBOSE=0
NON_INTERACTIVE=0
INSTALL_CRON_TEMPLATE=0

install_log() {
    if [[ "${VERBOSE}" -eq 1 ]]; then
        printf '%s\n' "$*"
    fi
}

run_cmd() {
    install_log "RUN: $*"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        return 0
    fi
    "$@"
}

write_file() {
    local target="${1:?target required}"
    local mode="${2:?mode required}"
    local content="${3:?content required}"
    local tmp_file

    install_log "WRITE: ${target}"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
        return 0
    fi

    [[ ! -L "${target}" ]] || {
        printf 'Refusing to overwrite symlink: %s\n' "${target}" >&2
        exit 1
    }

    tmp_file="$(mktemp "${target}.tmp.XXXXXX")"
    trap 'rm -f -- "${tmp_file}"' RETURN
    printf '%s\n' "${content}" > "${tmp_file}" || return 1
    chmod "${mode}" "${tmp_file}" || return 1
    mv -f -- "${tmp_file}" "${target}" || return 1
    chown root:root "${target}" || return 1
    chmod "${mode}" "${target}" || return 1
    trap - RETURN
}

path_mode() {
    stat -c '%a' -- "${1:?path required}"
}

path_owner_uid() {
    stat -c '%u' -- "${1:?path required}"
}

path_group_gid() {
    stat -c '%g' -- "${1:?path required}"
}

runtime_write_group_gid() {
    local gid
    gid="$(getent group "${RUNTIME_WRITE_GROUP}" 2>/dev/null | awk -F: '{ print $3 }')" || true
    [[ -n "${gid}" ]] || {
        printf 'Required runtime write group is missing: %s\n' "${RUNTIME_WRITE_GROUP}" >&2
        exit 8
    }
    printf '%s' "${gid}"
}

parse_args() {
    while (($# > 0)); do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --verbose) VERBOSE=1 ;;
            --non-interactive) NON_INTERACTIVE=1 ;;
            --install-cron-template) INSTALL_CRON_TEMPLATE=1 ;;
            *)
                printf 'Unknown installer option: %s\n' "$1" >&2
                exit 2
                ;;
        esac
        shift
    done
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        printf 'install.sh must be run as root.\n' >&2
        exit 4
    fi
}

verify_platform() {
    local os_id os_version arch kernel
    kernel="$(uname -s)"
    [[ "${kernel}" == "Linux" ]] || {
        printf 'MST supports Linux only.\n' >&2
        exit 8
    }

    if [[ -r /etc/os-release ]]; then
        os_id="$(awk -F= '/^ID=/{gsub(/"/, "", $2); print $2}' /etc/os-release)"
        os_version="$(awk -F= '/^VERSION_ID=/{gsub(/"/, "", $2); print $2}' /etc/os-release)"
    else
        printf 'Cannot read /etc/os-release.\n' >&2
        exit 8
    fi

    [[ "${os_id}" == "ubuntu" ]] || {
        printf 'MST foundation installer requires Ubuntu.\n' >&2
        exit 8
    }
    [[ "${os_version}" == "24.04" ]] || {
        printf 'MST foundation installer requires Ubuntu 24.04.\n' >&2
        exit 8
    }

    arch="$(uname -m)"
    case "${arch}" in
        x86_64|aarch64) ;;
        *)
            printf 'Unsupported architecture: %s\n' "${arch}" >&2
            exit 8
            ;;
    esac
}

verify_binaries() {
    local missing=0
    local name
    for name in bash awk sed grep cut sort uniq date stat find timeout flock install cp mv mkdir chmod chown chgrp getent uname id hostname mktemp; do
        if ! command -v "${name}" >/dev/null 2>&1; then
            printf 'Missing required binary: %s\n' "${name}" >&2
            missing=1
        fi
    done

    [[ "${missing}" -eq 0 ]] || exit 3
}

fail_unsafe_existing_destination() {
    local target="${1:?target required}"
    local reason="${2:?reason required}"
    printf 'Unsafe existing installer destination: %s (%s)\n' "${target}" "${reason}" >&2
    exit 8
}

assert_target() {
    case "${1:?path required}" in
        /usr/local/bin|/usr/local/bin/mst|/usr/local/lib/mst|/usr/local/lib/mst/*|/etc/mst|/etc/mst/*|/var/log/mst|/var/log/mst/*|/var/lib/mst|/var/lib/mst/*|/etc/logrotate.d/mst)
            ;;
        *)
            printf 'Unsafe installer target: %s\n' "${1}" >&2
            exit 8
            ;;
    esac
}

validate_existing_directory_destination() {
    local target="${1:?target required}"
    local actual_group expected_group
    assert_target "${target}"
    [[ -e "${target}" ]] || [[ -L "${target}" ]] || return 0
    [[ ! -L "${target}" ]] || fail_unsafe_existing_destination "${target}" "symbolic link"
    [[ -d "${target}" ]] || fail_unsafe_existing_destination "${target}" "expected directory"
    [[ "$(path_owner_uid "${target}")" == "0" ]] || fail_unsafe_existing_destination "${target}" "not owned by root"
    actual_group="$(path_group_gid "${target}")"
    if [[ "${target}" == "${CONFIG_DIR}" ]] || [[ "${target}" == "${STATE_DIR}" ]] || [[ "${target}" == "${STATE_DIR}/reports" ]] || [[ "${target}" == "${LOCK_DIR}" ]]; then
        expected_group="$(runtime_write_group_gid)"
        [[ "${actual_group}" == "0" ]] || [[ "${actual_group}" == "${expected_group}" ]] || fail_unsafe_existing_destination "${target}" "unexpected group"
    else
        [[ "${actual_group}" == "0" ]] || fail_unsafe_existing_destination "${target}" "group is not root"
    fi
}

validate_existing_file_destination() {
    local target="${1:?target required}"
    local actual_group expected_group
    assert_target "${target}"
    [[ -e "${target}" ]] || [[ -L "${target}" ]] || return 0
    [[ ! -L "${target}" ]] || fail_unsafe_existing_destination "${target}" "symbolic link"
    [[ -f "${target}" ]] || fail_unsafe_existing_destination "${target}" "expected regular file"
    [[ "$(path_owner_uid "${target}")" == "0" ]] || fail_unsafe_existing_destination "${target}" "not owned by root"
    actual_group="$(path_group_gid "${target}")"
    if [[ "${target}" == "${CONFIG_DIR}/config.conf" ]]; then
        expected_group="$(runtime_write_group_gid)"
        [[ "${actual_group}" == "0" ]] || [[ "${actual_group}" == "${expected_group}" ]] || fail_unsafe_existing_destination "${target}" "unexpected group"
    else
        [[ "${actual_group}" == "0" ]] || fail_unsafe_existing_destination "${target}" "group is not root"
    fi
}

validate_existing_destinations() {
    validate_existing_directory_destination "${BIN_DIR}"
    validate_existing_file_destination "${BIN_DIR}/mst"
    validate_existing_directory_destination "${LIB_DIR}"
    validate_existing_directory_destination "${CONFIG_DIR}"
    validate_existing_file_destination "${CONFIG_DIR}/config.conf"
    validate_existing_directory_destination "${LOG_DIR}"
    validate_existing_directory_destination "${STATE_DIR}"
    validate_existing_directory_destination "${STATE_DIR}/reports"
    validate_existing_directory_destination "${LOCK_DIR}"
    validate_existing_file_destination "${LOGROTATE_FILE}"
    if [[ "${INSTALL_CRON_TEMPLATE}" -eq 1 ]]; then
        validate_existing_file_destination "${CRON_TEMPLATE_FILE}"
    fi
}

source_package_roots() {
    printf '%s\n' \
        "mst" \
        "install.sh" \
        "uninstall.sh" \
        "commands" \
        "config" \
        "delivery" \
        "docs" \
        "inspectors" \
        "lib" \
        "renderers" \
        "schemas" \
        "scripts" \
        "templates" \
        "README.md" \
        "CHANGELOG.md" \
        "SECURITY.md"
}

validate_source_package() {
    local relative_path source_path symlink_path offending_path

    while IFS= read -r relative_path; do
        source_path="${PROJECT_ROOT}/${relative_path}"
        [[ -e "${source_path}" ]] || [[ -L "${source_path}" ]] || continue
        if [[ -L "${source_path}" ]]; then
            printf 'Unsafe source package symlink: %s\n' "${relative_path}" >&2
            exit 8
        fi
        if [[ -d "${source_path}" ]]; then
            symlink_path="$(find "${source_path}" -type l -print -quit)"
            if [[ -n "${symlink_path}" ]]; then
                offending_path="${symlink_path#${PROJECT_ROOT}/}"
                printf 'Unsafe source package symlink: %s\n' "${offending_path}" >&2
                exit 8
            fi
        fi
    done < <(source_package_roots)
}

create_secure_dir() {
    local target="${1:?target required}"
    local mode="${2:?mode required}"
    local owner_group="${3:-root}"

    assert_target "${target}"
    [[ ! -L "${target}" ]] || {
        printf 'Refusing to use symlink directory: %s\n' "${target}" >&2
        exit 8
    }
    run_cmd install -d -m "${mode}" "${target}" || return 1
    run_cmd chown "root:${owner_group}" "${target}" || return 1
    run_cmd chmod "${mode}" "${target}" || return 1
}

install_secure_file() {
    local source="${1:?source required}"
    local target="${2:?target required}"
    local mode="${3:?mode required}"
    local owner_group="${4:-root}"

    assert_target "${target}"
    [[ -f "${source}" ]] || {
        printf 'Installer source file missing: %s\n' "${source}" >&2
        exit 1
    }
    [[ ! -L "${target}" ]] || {
        printf 'Refusing to overwrite symlink: %s\n' "${target}" >&2
        exit 8
    }
    run_cmd install -m "${mode}" "${source}" "${target}" || return 1
    run_cmd chown "root:${owner_group}" "${target}" || return 1
    run_cmd chmod "${mode}" "${target}" || return 1
}

create_directories() {
    local path
    for path in "${BIN_DIR}" "${LIB_DIR}" \
        "${LIB_DIR}/lib" "${LIB_DIR}/commands" "${LIB_DIR}/inspectors" "${LIB_DIR}/renderers" "${LIB_DIR}/delivery" \
        "${LIB_DIR}/config" "${LIB_DIR}/templates" "${LIB_DIR}/docs" "${LIB_DIR}/schemas"; do
        create_secure_dir "${path}" 0755
    done
    create_secure_dir "${CONFIG_DIR}" 0750 "${RUNTIME_WRITE_GROUP}"
    create_secure_dir "${LOG_DIR}" 0750
    create_secure_dir "${STATE_DIR}" 2770 "${RUNTIME_WRITE_GROUP}"
    create_secure_dir "${STATE_DIR}/reports" 2770 "${RUNTIME_WRITE_GROUP}"
    create_secure_dir "${LOCK_DIR}" 2770 "${RUNTIME_WRITE_GROUP}"
}

normalize_runtime_write_tree() {
    local target

    [[ -d "${STATE_DIR}" ]] || return 0
    while IFS= read -r -d '' target; do
        assert_target "${target}"
        run_cmd chown "root:${RUNTIME_WRITE_GROUP}" "${target}" || return 1
        run_cmd chmod 2770 "${target}" || return 1
    done < <(find "${STATE_DIR}" -mindepth 1 -type d -print0)

    while IFS= read -r -d '' target; do
        assert_target "${target}"
        run_cmd chown "root:${RUNTIME_WRITE_GROUP}" "${target}" || return 1
        run_cmd chmod 0660 "${target}" || return 1
    done < <(find "${STATE_DIR}" -type f -print0)
}

install_binary() {
    assert_target "${BIN_DIR}/mst"
    write_file "${BIN_DIR}/mst" 0755 '#!/usr/bin/env bash
set -euo pipefail
umask 027
exec "/usr/local/lib/mst/mst" "$@"'
}

copy_tree() {
    local source_path="${1:?source path required}"
    local target_path="${2:?target path required}"
    local source_entry relative_path target_entry
    assert_target "${target_path}"

    while IFS= read -r -d '' source_entry; do
        relative_path="${source_entry#${source_path}/}"
        [[ "${relative_path}" != "${source_entry}" ]] || continue
        target_entry="${target_path}/${relative_path}"
        create_secure_dir "${target_entry}" 0755
    done < <(find "${source_path}" -mindepth 1 -type d -print0)

    while IFS= read -r -d '' source_entry; do
        relative_path="${source_entry#${source_path}/}"
        [[ "${relative_path}" != "${source_entry}" ]] || continue
        target_entry="${target_path}/${relative_path}"
        install_secure_file "${source_entry}" "${target_entry}" 0644
    done < <(find "${source_path}" -type f -print0)
}

install_runtime() {
    install_secure_file "${PROJECT_ROOT}/mst" "${LIB_DIR}/mst" 0755
    copy_tree "${PROJECT_ROOT}/lib" "${LIB_DIR}/lib"
    copy_tree "${PROJECT_ROOT}/commands" "${LIB_DIR}/commands"
    copy_tree "${PROJECT_ROOT}/inspectors" "${LIB_DIR}/inspectors"
    copy_tree "${PROJECT_ROOT}/renderers" "${LIB_DIR}/renderers"
    copy_tree "${PROJECT_ROOT}/delivery" "${LIB_DIR}/delivery"
    copy_tree "${PROJECT_ROOT}/config" "${LIB_DIR}/config"
    copy_tree "${PROJECT_ROOT}/templates" "${LIB_DIR}/templates"
    copy_tree "${PROJECT_ROOT}/docs" "${LIB_DIR}/docs"
    copy_tree "${PROJECT_ROOT}/schemas" "${LIB_DIR}/schemas"
    install_secure_file "${PROJECT_ROOT}/README.md" "${LIB_DIR}/README.md" 0644
    install_secure_file "${PROJECT_ROOT}/CHANGELOG.md" "${LIB_DIR}/CHANGELOG.md" 0644
    install_secure_file "${PROJECT_ROOT}/SECURITY.md" "${LIB_DIR}/SECURITY.md" 0644
}

install_config_template() {
    local target="${CONFIG_DIR}/config.conf"
    assert_target "${target}"
    if [[ -f "${target}" ]]; then
        if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
            printf 'Existing configuration preserved in non-interactive mode: %s\n' "${target}"
        else
            printf 'Existing configuration preserved: %s\n' "${target}"
        fi
        run_cmd chown "root:${RUNTIME_WRITE_GROUP}" "${target}" || return 1
        run_cmd chmod 0640 "${target}" || return 1
        return 0
    fi
    install_secure_file "${PROJECT_ROOT}/config/config.conf.example" "${target}" 0640 "${RUNTIME_WRITE_GROUP}"
}

install_logrotate() {
    assert_target "${LOGROTATE_FILE}"
    install_secure_file "${PROJECT_ROOT}/templates/logrotate.conf" "${LOGROTATE_FILE}" 0644
}

install_optional_cron_template() {
    [[ "${INSTALL_CRON_TEMPLATE}" -eq 1 ]] || return 0
    assert_target "${CRON_TEMPLATE_FILE}"
    install_secure_file "${PROJECT_ROOT}/templates/mst.cron.example" "${CRON_TEMPLATE_FILE}" 0644
}

verify_owner_root() {
    local target="${1:?target required}"
    local expected_group="${2:-root}"
    [[ "$(path_owner_uid "${target}")" == "0" ]] || {
        printf 'Installed path is not owned by root: %s\n' "${target}" >&2
        return 1
    }
    if [[ "${expected_group}" == "root" ]]; then
        [[ "$(path_group_gid "${target}")" == "0" ]] || {
            printf 'Installed path group is not root: %s\n' "${target}" >&2
            return 1
        }
    else
        [[ "$(path_group_gid "${target}")" == "$(runtime_write_group_gid)" ]] || {
            printf 'Installed path group is not %s: %s\n' "${expected_group}" "${target}" >&2
            return 1
        }
    fi
}

verify_mode_exact() {
    local target="${1:?target required}"
    local expected_mode="${2:?mode required}"
    local actual_mode
    actual_mode="$(path_mode "${target}")" || return 1
    actual_mode="$(printf '%s' "${actual_mode}" | sed 's/^0*//')"
    expected_mode="$(printf '%s' "${expected_mode}" | sed 's/^0*//')"
    [[ -n "${actual_mode}" ]] || actual_mode="0"
    [[ -n "${expected_mode}" ]] || expected_mode="0"
    [[ "${actual_mode}" == "${expected_mode}" ]] || {
        printf 'Installed path has mode %s, expected %s: %s\n' "${actual_mode}" "${expected_mode}" "${target}" >&2
        return 1
    }
}

verify_no_group_or_world_write() {
    local target="${1:?target required}"
    local mode group_digit other_digit
    mode="$(path_mode "${target}")" || return 1
    group_digit="${mode: -2:1}"
    other_digit="${mode: -1}"
    if (( (10#${group_digit} & 2) != 0 )) || (( (10#${other_digit} & 2) != 0 )); then
        printf 'Installed path is group/world writable: %s\n' "${target}" >&2
        return 1
    fi
}

verify_no_world_write() {
    local target="${1:?target required}"
    local mode other_digit
    mode="$(path_mode "${target}")" || return 1
    other_digit="${mode: -1}"
    if (( (10#${other_digit} & 2) != 0 )); then
        printf 'Installed path is world writable: %s\n' "${target}" >&2
        return 1
    fi
}

verify_installed_path() {
    local target="${1:?target required}"
    local expected_mode="${2:?mode required}"
    local expected_group="${3:-root}"
    [[ -e "${target}" ]] || return 0
    [[ ! -L "${target}" ]] || {
        printf 'Installed path unexpectedly symlinked: %s\n' "${target}" >&2
        return 1
    }
    verify_owner_root "${target}" "${expected_group}"
    verify_mode_exact "${target}" "${expected_mode}"
    if [[ "${expected_group}" == "root" ]]; then
        verify_no_group_or_world_write "${target}"
    else
        verify_no_world_write "${target}"
    fi
}

verify_runtime_tree_permissions() {
    local target
    local failed=0
    [[ -d "${LIB_DIR}" ]] || return 0
    while IFS= read -r -d '' target; do
        verify_installed_path "${target}" 0755 || failed=1
    done < <(find "${LIB_DIR}" -type d -print0)

    while IFS= read -r -d '' target; do
        case "${target}" in
            "${LIB_DIR}/mst")
                verify_installed_path "${target}" 0755 || failed=1
                ;;
            *)
                verify_installed_path "${target}" 0644 || failed=1
                ;;
        esac
    done < <(find "${LIB_DIR}" -type f -print0)
    return "${failed}"
}

verify_install_permissions() {
    local failed=0
    [[ "${DRY_RUN}" -eq 1 ]] && return 0

    verify_installed_path "${BIN_DIR}/mst" 0755 || failed=1
    verify_runtime_tree_permissions || failed=1
    verify_installed_path "${CONFIG_DIR}" 0750 "${RUNTIME_WRITE_GROUP}" || failed=1
    verify_installed_path "${CONFIG_DIR}/config.conf" 0640 "${RUNTIME_WRITE_GROUP}" || failed=1
    verify_installed_path "${LOG_DIR}" 0750 || failed=1
    verify_installed_path "${STATE_DIR}" 2770 "${RUNTIME_WRITE_GROUP}" || failed=1
    verify_installed_path "${STATE_DIR}/reports" 2770 "${RUNTIME_WRITE_GROUP}" || failed=1
    verify_installed_path "${LOCK_DIR}" 2770 "${RUNTIME_WRITE_GROUP}" || failed=1
    verify_installed_path "${LOGROTATE_FILE}" 0644 || failed=1
    if [[ "${INSTALL_CRON_TEMPLATE}" -eq 1 ]]; then
        verify_installed_path "${CRON_TEMPLATE_FILE}" 0644 || failed=1
    fi
    return "${failed}"
}

show_plan() {
    cat <<EOF
MST foundation installer plan
  Binary: ${BIN_DIR}/mst
  Runtime: ${LIB_DIR}/
  Config:  ${CONFIG_DIR}/config.conf
  Logs:    ${LOG_DIR}/
  State:   ${STATE_DIR}/
  Rotate:  ${LOGROTATE_FILE}
EOF
    if [[ "${INSTALL_CRON_TEMPLATE}" -eq 1 ]]; then
        printf '  Cron:    %s\n' "${CRON_TEMPLATE_FILE}"
    fi
    if [[ "${NON_INTERACTIVE}" -eq 1 ]]; then
        printf '  Mode:    non-interactive\n'
    fi
}

main() {
    parse_args "$@"
    require_root
    verify_platform
    verify_binaries
    validate_source_package
    validate_existing_destinations
    show_plan
    create_directories
    normalize_runtime_write_tree
    install_binary
    install_runtime
    install_config_template
    install_logrotate
    install_optional_cron_template
    verify_install_permissions
    printf 'MST foundation installation complete.\n'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
