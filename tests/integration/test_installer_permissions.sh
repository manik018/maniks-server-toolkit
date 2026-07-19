#!/usr/bin/env bash
# Validate deterministic installer permissions independent of source modes and umask.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/installer-permissions"
SOURCE_DIR="${TMP_DIR}/source"
DEST_DIR="${TMP_DIR}/dest"
MODE_DB="${TMP_DIR}/modes.db"

rm -rf "${TMP_DIR}"
mkdir -p "${SOURCE_DIR}" "${DEST_DIR}"

make_source_tree() {
    local dir file_path
    mkdir -p \
        "${SOURCE_DIR}/lib" \
        "${SOURCE_DIR}/commands" \
        "${SOURCE_DIR}/inspectors/health" \
        "${SOURCE_DIR}/renderers" \
        "${SOURCE_DIR}/delivery" \
        "${SOURCE_DIR}/config" \
        "${SOURCE_DIR}/templates" \
        "${SOURCE_DIR}/docs" \
        "${SOURCE_DIR}/schemas"

    printf '#!/usr/bin/env bash\nprintf mst\n' > "${SOURCE_DIR}/mst"
    printf 'printf lib\n' > "${SOURCE_DIR}/lib/runtime.sh"
    printf 'printf command\n' > "${SOURCE_DIR}/commands/health.sh"
    printf 'printf inspector\n' > "${SOURCE_DIR}/inspectors/health/cpu.sh"
    printf 'printf renderer\n' > "${SOURCE_DIR}/renderers/health_text.sh"
    printf 'printf delivery\n' > "${SOURCE_DIR}/delivery/telegram.sh"
    printf 'MST_CONFIG_SCHEMA_VERSION="1"\n' > "${SOURCE_DIR}/config/config.conf.example"
    printf 'logrotate\n' > "${SOURCE_DIR}/templates/logrotate.conf"
    printf 'cron\n' > "${SOURCE_DIR}/templates/mst.cron.example"
    printf 'docs\n' > "${SOURCE_DIR}/docs/readme.md"
    printf '{}\n' > "${SOURCE_DIR}/schemas/schema.json"
    printf 'readme\n' > "${SOURCE_DIR}/README.md"
    printf 'changes\n' > "${SOURCE_DIR}/CHANGELOG.md"
    printf 'security\n' > "${SOURCE_DIR}/SECURITY.md"

    while IFS= read -r -d '' dir; do
        chmod 0777 "${dir}"
    done < <(find "${SOURCE_DIR}" -type d -print0)
    while IFS= read -r -d '' file_path; do
        chmod 0666 "${file_path}"
    done < <(find "${SOURCE_DIR}" -type f -print0)
    chmod 0777 "${SOURCE_DIR}/mst"
}

configure_installer_paths() {
    PROJECT_ROOT="${SOURCE_DIR}"
    PREFIX="${DEST_DIR}/usr/local"
    BIN_DIR="${PREFIX}/bin"
    LIB_DIR="${PREFIX}/lib/mst"
    CONFIG_DIR="${DEST_DIR}/etc/mst"
    LOG_DIR="${DEST_DIR}/var/log/mst"
    STATE_DIR="${DEST_DIR}/var/lib/mst"
    LOCK_DIR="${STATE_DIR}/locks"
    LOGROTATE_FILE="${DEST_DIR}/etc/logrotate.d/mst"
    CRON_TEMPLATE_FILE="${CONFIG_DIR}/mst.cron.example"
    DRY_RUN=0
    VERBOSE=0
    NON_INTERACTIVE=1
    INSTALL_CRON_TEMPLATE=1
}

# shellcheck source=../../install.sh
source "${ROOT_DIR}/install.sh"

record_mode() {
    local path="${1:?path required}"
    local mode="${2:?mode required}"
    grep -F -v "${path}|" "${MODE_DB}" 2>/dev/null > "${MODE_DB}.tmp" || true
    printf '%s|%s\n' "${path}" "${mode}" >> "${MODE_DB}.tmp"
    mv -f -- "${MODE_DB}.tmp" "${MODE_DB}"
}

install() {
    local mode="" make_dir=0
    if [[ "${1:-}" == "-d" ]]; then
        make_dir=1
        shift
    fi
    if [[ "${1:-}" == "-m" ]]; then
        mode="${2:?mode required}"
        shift 2
    fi
    if [[ "${make_dir}" -eq 1 ]]; then
        mkdir -p "${1:?target required}"
        command chmod "${mode}" "${1}" 2>/dev/null || true
        record_mode "${1}" "${mode}"
    else
        local source="${1:?source required}"
        local target="${2:?target required}"
        mkdir -p "$(dirname -- "${target}")"
        cp -- "${source}" "${target}"
        command chmod "${mode}" "${target}" 2>/dev/null || true
        record_mode "${target}" "${mode}"
    fi
}

chmod() {
    local mode="${1:?mode required}"
    shift || true
    local path
    for path in "$@"; do
        command chmod "${mode}" "${path}" 2>/dev/null || true
        record_mode "${path}" "${mode}"
    done
}

assert_target() {
    case "${1:?path required}" in
        "${DEST_DIR}"/*) return 0 ;;
        *) printf 'test attempted unsafe target: %s\n' "${1}" >&2; return 1 ;;
    esac
}

chown() {
    if [[ "${MST_TEST_CHOWN_FAIL:-0}" -eq 1 ]]; then
        return 1
    fi
    return 0
}

path_owner_uid() {
    printf '0'
}

path_group_gid() {
    printf '0'
}

path_mode() {
    local target="${1:?target required}"
    local recorded
    recorded="$(awk -F'|' -v target="${target}" '$1 == target { value=$2 } END { print value }' "${MODE_DB}" 2>/dev/null || true)"
    if [[ -n "${recorded}" ]]; then
        printf '%s' "${recorded}"
    else
        stat -c '%a' -- "${target}"
    fi
}

run_install_steps() {
    create_directories
    install_binary
    install_runtime
    install_config_template
    install_logrotate
    install_optional_cron_template
    verify_install_permissions
}

assert_mode() {
    local path="${1:?path required}"
    local expected="${2:?mode required}"
    local actual
    actual="$(path_mode "${path}")"
    actual="$(printf '%s' "${actual}" | sed 's/^0*//')"
    expected="$(printf '%s' "${expected}" | sed 's/^0*//')"
    [[ -n "${actual}" ]] || actual="0"
    [[ -n "${expected}" ]] || expected="0"
    [[ "${actual}" == "${expected}" ]] || {
        printf 'mode mismatch for %s: expected %s got %s\n' "${path}" "${expected}" "${actual}" >&2
        exit 1
    }
}

assert_no_writable_paths() {
    local root="${1:?root required}"
    if find "${root}" -type d -perm /022 | grep -q .; then
        printf 'group/world writable directory remained under %s\n' "${root}" >&2
        exit 1
    fi
    if find "${root}" -type f -perm /022 | grep -q .; then
        printf 'group/world writable file remained under %s\n' "${root}" >&2
        exit 1
    fi
}

make_source_tree
configure_installer_paths

umask 000
run_install_steps
assert_mode "${LIB_DIR}" 755
assert_mode "${LIB_DIR}/lib" 755
assert_mode "${LIB_DIR}/lib/runtime.sh" 644
assert_mode "${LIB_DIR}/commands/health.sh" 644
assert_mode "${LIB_DIR}/mst" 755
assert_mode "${BIN_DIR}/mst" 755
assert_mode "${CONFIG_DIR}" 750
assert_mode "${CONFIG_DIR}/config.conf" 600
assert_mode "${LOG_DIR}" 750
assert_mode "${STATE_DIR}" 750
assert_mode "${LOCK_DIR}" 750
assert_no_writable_paths "${LIB_DIR}"

umask 077
run_install_steps
assert_mode "${LIB_DIR}/lib/runtime.sh" 644
assert_mode "${LIB_DIR}/mst" 755
assert_mode "${CONFIG_DIR}/config.conf" 600
assert_no_writable_paths "${LIB_DIR}"

chmod 0666 "${LIB_DIR}/lib/runtime.sh"
if verify_runtime_tree_permissions >/dev/null 2>&1; then
    printf 'verification should fail for group/world writable runtime file.\n' >&2
    exit 1
fi
chmod 0644 "${LIB_DIR}/lib/runtime.sh"

MST_TEST_CHOWN_FAIL=1
if install_secure_file "${SOURCE_DIR}/README.md" "${LIB_DIR}/README.md" 0644 >/dev/null 2>&1; then
    printf 'permission or ownership normalization failure should return non-zero.\n' >&2
    exit 1
fi
MST_TEST_CHOWN_FAIL=0

printf 'test_installer_permissions.sh passed.\n'
