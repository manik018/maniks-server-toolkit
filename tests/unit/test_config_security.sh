#!/usr/bin/env bash
# Validate configuration ownership and permission hardening.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/config-security"
mkdir -p "${TMP_DIR}"
chmod 0700 "${TMP_DIR}"

write_config() {
    local target="${1:?target required}"
    cat > "${target}" <<'EOF'
MST_CONFIG_SCHEMA_VERSION="1"
MST_LOG_LEVEL="INFO"
EOF
}

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"

perm_config="${TMP_DIR}/permissions.conf"
write_config "${perm_config}"

mst_fs_path_mode_octal() {
    if [[ "${1}" == "${perm_config}" ]]; then
        printf '666'
    else
        stat -c '%a' -- "${1}"
    fi
}

if ( mst_config_load_file "${perm_config}" ) >/dev/null 2>&1; then
    printf 'world-writable config should be rejected.\n' >&2
    exit 1
fi

owner_config="${TMP_DIR}/ownership.conf"
write_config "${owner_config}"
chmod 0600 "${owner_config}"

mst_fs_path_owner_uid() {
    if [[ "${1}" == "${owner_config}" ]]; then
        printf '424242'
    else
        stat -c '%u' -- "${1}"
    fi
}

if ( mst_config_load_file "${owner_config}" ) >/dev/null 2>&1; then
    printf 'unsafe config ownership should be rejected.\n' >&2
    exit 1
fi

printf 'test_config_security.sh passed.\n'
