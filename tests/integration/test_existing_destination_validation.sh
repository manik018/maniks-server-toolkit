#!/usr/bin/env bash
# Validate installer preflight checks for existing destination paths.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/existing-destination-validation"
DEST_DIR="${TMP_DIR}/dest"
MODE_DB="${TMP_DIR}/ownership.db"

rm -rf -- "${TMP_DIR}"
mkdir -p "${DEST_DIR}"
: > "${MODE_DB}"

unset PREFIX BIN_DIR LIB_DIR CONFIG_DIR LOG_DIR STATE_DIR LOCK_DIR LOGROTATE_FILE CRON_TEMPLATE_FILE

# shellcheck source=../../install.sh
source "${ROOT_DIR}/install.sh"

configure_paths() {
    BIN_DIR="${DEST_DIR}/usr/local/bin"
    LIB_DIR="${DEST_DIR}/usr/local/lib/mst"
    CONFIG_DIR="${DEST_DIR}/etc/mst"
    LOG_DIR="${DEST_DIR}/var/log/mst"
    STATE_DIR="${DEST_DIR}/var/lib/mst"
    LOCK_DIR="${STATE_DIR}/locks"
    LOGROTATE_FILE="${DEST_DIR}/etc/logrotate.d/mst"
    CRON_TEMPLATE_FILE="${CONFIG_DIR}/mst.cron.example"
    INSTALL_CRON_TEMPLATE=1
    MST_TEST_WRITE_COUNT=0
    MST_TEST_SYMLINK_PATH=""
}

assert_target() {
    case "${1:?path required}" in
        "${DEST_DIR}"/*) return 0 ;;
        *) printf 'test attempted unsafe target: %s\n' "${1}" >&2; return 1 ;;
    esac
}

record_owner() {
    local path="${1:?path required}"
    local uid="${2:?uid required}"
    local gid="${3:?gid required}"
    awk -F'|' -v target="${path}" '$1 != target { print }' "${MODE_DB}" > "${MODE_DB}.tmp" 2>/dev/null || true
    printf '%s|%s|%s\n' "${path}" "${uid}" "${gid}" >> "${MODE_DB}.tmp"
    mv -f -- "${MODE_DB}.tmp" "${MODE_DB}"
}

path_owner_uid() {
    local target="${1:?target required}"
    awk -F'|' -v target="${target}" '$1 == target { uid=$2 } END { print uid ? uid : 0 }' "${MODE_DB}"
}

path_group_gid() {
    local target="${1:?target required}"
    awk -F'|' -v target="${target}" '$1 == target { gid=$3 } END { print gid ? gid : 0 }' "${MODE_DB}"
}

test_path_is_symlink() {
    local target="${1:?target required}"
    [[ -n "${MST_TEST_SYMLINK_PATH}" ]] && [[ "${target}" == "${MST_TEST_SYMLINK_PATH}" ]]
}

validate_existing_directory_destination() {
    local target="${1:?target required}"
    assert_target "${target}"
    [[ -e "${target}" ]] || test_path_is_symlink "${target}" || return 0
    ! test_path_is_symlink "${target}" || fail_unsafe_existing_destination "${target}" "symbolic link"
    [[ -d "${target}" ]] || fail_unsafe_existing_destination "${target}" "expected directory"
    [[ "$(path_owner_uid "${target}")" == "0" ]] || fail_unsafe_existing_destination "${target}" "not owned by root"
    [[ "$(path_group_gid "${target}")" == "0" ]] || fail_unsafe_existing_destination "${target}" "group is not root"
}

validate_existing_file_destination() {
    local target="${1:?target required}"
    assert_target "${target}"
    [[ -e "${target}" ]] || test_path_is_symlink "${target}" || return 0
    ! test_path_is_symlink "${target}" || fail_unsafe_existing_destination "${target}" "symbolic link"
    [[ -f "${target}" ]] || fail_unsafe_existing_destination "${target}" "expected regular file"
    [[ "$(path_owner_uid "${target}")" == "0" ]] || fail_unsafe_existing_destination "${target}" "not owned by root"
    [[ "$(path_group_gid "${target}")" == "0" ]] || fail_unsafe_existing_destination "${target}" "group is not root"
}

create_secure_dir() {
    MST_TEST_WRITE_COUNT=$(( MST_TEST_WRITE_COUNT + 1 ))
}

install_binary() {
    MST_TEST_WRITE_COUNT=$(( MST_TEST_WRITE_COUNT + 1 ))
}

install_runtime() {
    MST_TEST_WRITE_COUNT=$(( MST_TEST_WRITE_COUNT + 1 ))
}

install_config_template() {
    MST_TEST_WRITE_COUNT=$(( MST_TEST_WRITE_COUNT + 1 ))
}

install_logrotate() {
    MST_TEST_WRITE_COUNT=$(( MST_TEST_WRITE_COUNT + 1 ))
}

install_optional_cron_template() {
    MST_TEST_WRITE_COUNT=$(( MST_TEST_WRITE_COUNT + 1 ))
}

verify_install_permissions() {
    return 0
}

prepare_valid_destinations() {
    rm -rf -- "${DEST_DIR}"
    mkdir -p "${BIN_DIR}" "${LIB_DIR}" "${CONFIG_DIR}" "${LOG_DIR}" "${LOCK_DIR}" "$(dirname -- "${LOGROTATE_FILE}")"
    printf 'wrapper\n' > "${BIN_DIR}/mst"
    printf 'config\n' > "${CONFIG_DIR}/config.conf"
    printf 'rotate\n' > "${LOGROTATE_FILE}"
    printf 'cron\n' > "${CRON_TEMPLATE_FILE}"
    : > "${MODE_DB}"
}

run_mock_install_after_validation() {
    validate_existing_destinations
    create_secure_dir "${BIN_DIR}" 0755
    install_binary
    install_runtime
    install_config_template
    install_logrotate
    install_optional_cron_template
    verify_install_permissions
}

expect_validation_failure() {
    local expected_text="${1:?message required}"
    local output status
    set +e
    output="$(run_mock_install_after_validation 2>&1)"
    status=$?
    set -e
    [[ "${status}" -ne 0 ]] || {
        printf 'validation should have failed: %s\n' "${expected_text}" >&2
        exit 1
    }
    [[ "${output}" == *"${expected_text}"* ]] || {
        printf 'expected validation output to contain %s, got: %s\n' "${expected_text}" "${output}" >&2
        exit 1
    }
    [[ "${MST_TEST_WRITE_COUNT}" == "0" ]] || {
        printf 'validation failure occurred after writes.\n' >&2
        exit 1
    }
}

configure_paths
prepare_valid_destinations
validate_existing_destinations

run_mock_install_after_validation
[[ "${MST_TEST_WRITE_COUNT}" -gt 0 ]] || exit 1

configure_paths
prepare_valid_destinations
MST_TEST_SYMLINK_PATH="${LIB_DIR}"
expect_validation_failure "symbolic link"

configure_paths
prepare_valid_destinations
rm -rf -- "${LOG_DIR}"
printf 'not a directory\n' > "${LOG_DIR}"
expect_validation_failure "expected directory"

configure_paths
prepare_valid_destinations
record_owner "${CONFIG_DIR}" "1000" "0"
expect_validation_failure "not owned by root"

configure_paths
prepare_valid_destinations
MST_TEST_SYMLINK_PATH="${BIN_DIR}/mst"
expect_validation_failure "symbolic link"

configure_paths
[[ "${BIN_DIR}" == "${DEST_DIR}/usr/local/bin" ]] || exit 1
[[ "${LIB_DIR}" == "${DEST_DIR}/usr/local/lib/mst" ]] || exit 1
[[ "${CONFIG_DIR}" == "${DEST_DIR}/etc/mst" ]] || exit 1

rm -rf -- "${TMP_DIR}"
[[ ! -e "${TMP_DIR}" ]] || exit 1

printf 'test_existing_destination_validation.sh passed.\n'
