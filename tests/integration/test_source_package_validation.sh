#!/usr/bin/env bash
# Validate installer source package symlink preflight checks.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/source-package-validation"
SOURCE_DIR="${TMP_DIR}/source"
DEST_DIR="${TMP_DIR}/dest"

rm -rf -- "${TMP_DIR}"
mkdir -p "${SOURCE_DIR}" "${DEST_DIR}"

make_clean_source() {
    mkdir -p \
        "${SOURCE_DIR}/commands" \
        "${SOURCE_DIR}/config" \
        "${SOURCE_DIR}/delivery" \
        "${SOURCE_DIR}/docs" \
        "${SOURCE_DIR}/inspectors" \
        "${SOURCE_DIR}/lib" \
        "${SOURCE_DIR}/renderers" \
        "${SOURCE_DIR}/schemas" \
        "${SOURCE_DIR}/scripts" \
        "${SOURCE_DIR}/templates"

    printf '#!/usr/bin/env bash\n' > "${SOURCE_DIR}/mst"
    printf '#!/usr/bin/env bash\n' > "${SOURCE_DIR}/install.sh"
    printf '#!/usr/bin/env bash\n' > "${SOURCE_DIR}/uninstall.sh"
    printf 'command\n' > "${SOURCE_DIR}/commands/health.sh"
    printf 'config\n' > "${SOURCE_DIR}/config/config.conf.example"
    printf 'delivery\n' > "${SOURCE_DIR}/delivery/telegram.sh"
    printf 'docs\n' > "${SOURCE_DIR}/docs/release.md"
    printf 'inspector\n' > "${SOURCE_DIR}/inspectors/health.sh"
    printf 'lib\n' > "${SOURCE_DIR}/lib/runtime.sh"
    printf 'renderer\n' > "${SOURCE_DIR}/renderers/health_text.sh"
    printf '{}\n' > "${SOURCE_DIR}/schemas/mrrf1.schema.json"
    printf 'script\n' > "${SOURCE_DIR}/scripts/release-check.sh"
    printf 'template\n' > "${SOURCE_DIR}/templates/logrotate.conf"
    printf 'readme\n' > "${SOURCE_DIR}/README.md"
    printf 'changes\n' > "${SOURCE_DIR}/CHANGELOG.md"
    printf 'security\n' > "${SOURCE_DIR}/SECURITY.md"
}

unset PREFIX BIN_DIR LIB_DIR CONFIG_DIR LOG_DIR STATE_DIR LOCK_DIR LOGROTATE_FILE CRON_TEMPLATE_FILE

# shellcheck source=../../install.sh
source "${ROOT_DIR}/install.sh"

configure_installer_fixture() {
    PROJECT_ROOT="${SOURCE_DIR}"
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
    MST_TEST_FIND_SYMLINK=""
}

assert_target() {
    case "${1:?path required}" in
        "${DEST_DIR}"/*) return 0 ;;
        *) printf 'test attempted unsafe target: %s\n' "${1}" >&2; return 1 ;;
    esac
}

find() {
    local path="${1:?path required}"
    shift || true
    if [[ -n "${MST_TEST_FIND_SYMLINK:-}" ]] && [[ "${MST_TEST_FIND_SYMLINK}" == "${path}"/* ]]; then
        printf '%s\n' "${MST_TEST_FIND_SYMLINK}"
    fi
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

validate_existing_destinations() {
    return 0
}

verify_install_permissions() {
    return 0
}

run_mock_install_after_source_validation() {
    validate_source_package
    validate_existing_destinations
    create_secure_dir "${BIN_DIR}" 0755
    install_binary
    install_runtime
    install_config_template
    install_logrotate
    install_optional_cron_template
    verify_install_permissions
}

expect_source_validation_failure() {
    local relative_path="${1:?relative path required}"
    local output status

    MST_TEST_FIND_SYMLINK="${SOURCE_DIR}/${relative_path}"
    MST_TEST_WRITE_COUNT=0

    set +e
    output="$(run_mock_install_after_source_validation 2>&1)"
    status=$?
    set -e

    [[ "${status}" -ne 0 ]] || {
        printf 'source validation should have failed for %s\n' "${relative_path}" >&2
        exit 1
    }
    [[ "${output}" == *"Unsafe source package symlink: ${relative_path}"* ]] || {
        printf 'unexpected source validation output: %s\n' "${output}" >&2
        exit 1
    }
    [[ "${MST_TEST_WRITE_COUNT}" == "0" ]] || {
        printf 'source validation failure occurred after writes.\n' >&2
        exit 1
    }
}

make_clean_source
configure_installer_fixture
validate_source_package

run_mock_install_after_source_validation
[[ "${MST_TEST_WRITE_COUNT}" -gt 0 ]] || exit 1

configure_installer_fixture
expect_source_validation_failure "lib/runtime.sh"

configure_installer_fixture
expect_source_validation_failure "scripts/release-check.sh"

configure_installer_fixture
expect_source_validation_failure "templates/logrotate.conf"

configure_installer_fixture
[[ "${BIN_DIR}" == "${DEST_DIR}/usr/local/bin" ]] || exit 1
[[ "${LIB_DIR}" == "${DEST_DIR}/usr/local/lib/mst" ]] || exit 1

rm -rf -- "${TMP_DIR}"
[[ ! -e "${TMP_DIR}" ]] || exit 1

printf 'test_source_package_validation.sh passed.\n'
