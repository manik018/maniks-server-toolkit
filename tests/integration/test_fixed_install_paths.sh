#!/usr/bin/env bash
# Validate MST installer fixed-path behavior and unsupported override rejection.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/fixed-install-paths"

rm -rf -- "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

assert_override_rejected() {
    local name="${1:?name required}"
    local value="${TMP_DIR}/${name,,}"
    local output status

    set +e
    output="$(env "${name}=${value}" bash "${ROOT_DIR}/install.sh" --dry-run 2>&1)"
    status=$?
    set -e

    [[ "${status}" -ne 0 ]] || {
        printf '%s override should be rejected.\n' "${name}" >&2
        exit 1
    }
    [[ "${output}" == *"Custom install paths are unsupported"* ]] || exit 1
    [[ "${output}" == *"unset ${name}"* ]] || exit 1
    [[ "${output}" != *"MST foundation installer plan"* ]] || exit 1
    [[ ! -e "${value}" ]] || {
        printf '%s override created filesystem state before rejection.\n' "${name}" >&2
        exit 1
    }
}

for name in PREFIX BIN_DIR LIB_DIR CONFIG_DIR; do
    assert_override_rejected "${name}"
done

(
    unset PREFIX BIN_DIR LIB_DIR CONFIG_DIR LOG_DIR STATE_DIR LOCK_DIR LOGROTATE_FILE CRON_TEMPLATE_FILE

    # shellcheck source=../../install.sh
    source "${ROOT_DIR}/install.sh"

    [[ "${BIN_DIR}" == "/usr/local/bin" ]] || exit 1
    [[ "${LIB_DIR}" == "/usr/local/lib/mst" ]] || exit 1
    [[ "${CONFIG_DIR}" == "/etc/mst" ]] || exit 1
    [[ "${LOG_DIR}" == "/var/log/mst" ]] || exit 1
    [[ "${STATE_DIR}" == "/var/lib/mst" ]] || exit 1
    [[ "${LOCK_DIR}" == "/var/lib/mst/locks" ]] || exit 1

    captured_target=""
    captured_mode=""
    captured_content=""
    write_file() {
        captured_target="${1:?target required}"
        captured_mode="${2:?mode required}"
        captured_content="${3:?content required}"
    }

    install_binary
    [[ "${captured_target}" == "/usr/local/bin/mst" ]] || exit 1
    [[ "${captured_mode}" == "0755" ]] || exit 1
    [[ "${captured_content}" == *'exec "/usr/local/lib/mst/mst" "$@"'* ]] || exit 1
)

set +e
(
    PREFIX="/tmp/unsupported"
    # shellcheck source=../../uninstall.sh
    source "${ROOT_DIR}/uninstall.sh"

    require_root() {
        return 0
    }

    if main --dry-run >/dev/null 2>&1; then
        printf 'uninstaller should retain existing allowlist rejection for non-canonical PREFIX.\n' >&2
        exit 1
    fi
)
uninstaller_status=$?
set -e
[[ "${uninstaller_status}" -ne 0 ]] || exit 1

rm -rf -- "${TMP_DIR}"
[[ ! -e "${TMP_DIR}" ]] || exit 1

printf 'test_fixed_install_paths.sh passed.\n'
