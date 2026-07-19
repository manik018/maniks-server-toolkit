#!/usr/bin/env bash
# Validate configuration defaults and schema handling.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/config"
mkdir -p "${TMP_DIR}"

cat > "${TMP_DIR}/config.conf" <<'EOF'
MST_CONFIG_SCHEMA_VERSION="1"
MST_LOG_LEVEL="DEBUG"
MST_OUTPUT_MODE="text"
MST_LOG_DIR="/tmp/mst-test-logs"
MST_STATE_DIR="/tmp/mst-test-state"
MST_LOCK_DIR="/tmp/mst-test-state/locks"
MST_TIMEOUT_SECONDS="15"
EOF

export MST_CONFIG_FILE="${TMP_DIR}/config.conf"

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
mst_runtime_init

mst_fs_validate_trusted_config_file() {
    return 0
}

mst_fs_validate_runtime_write_paths() {
    export MST_LOG_FILE="${MST_LOG_DIR}/mst.log"
    return 0
}

run_config_precedence_case() {
    local expected_output="${1:?expected output required}"
    shift

    unset MST_OUTPUT_MODE MST_GLOBAL_OUTPUT_MODE MST_GLOBAL_CONFIG_FILE MST_ENV_OUTPUT_MODE
    mst_parse_cli "$@" || true
    mst_runtime_init
    mst_apply_global_cli_options
    mst_config_load
    [[ "${MST_OUTPUT_MODE}" == "${expected_output}" ]] || {
        printf 'expected output mode %s, got %s\n' "${expected_output}" "${MST_OUTPUT_MODE}" >&2
        exit 1
    }
}

mst_config_load

[[ "${MST_LOG_LEVEL}" == "DEBUG" ]] || exit 1
[[ "${MST_TIMEOUT_SECONDS}" == "15" ]] || exit 1
[[ "${MST_OUTPUT_MODE}" == "text" ]] || exit 1

cat > "${TMP_DIR}/defaults-only.conf" <<'EOF'
MST_CONFIG_SCHEMA_VERSION="1"
MST_LOG_DIR="/tmp/mst-test-logs"
MST_STATE_DIR="/tmp/mst-test-state"
MST_LOCK_DIR="/tmp/mst-test-state/locks"
EOF

export MST_CONFIG_FILE="${TMP_DIR}/defaults-only.conf"
run_config_precedence_case "text" health
run_config_precedence_case "json" --output json health
run_config_precedence_case "text" --output text health
run_config_precedence_case "json" health --output json

cat > "${TMP_DIR}/json-config.conf" <<'EOF'
MST_CONFIG_SCHEMA_VERSION="1"
MST_OUTPUT_MODE="json"
MST_LOG_DIR="/tmp/mst-test-logs"
MST_STATE_DIR="/tmp/mst-test-state"
MST_LOCK_DIR="/tmp/mst-test-state/locks"
EOF

export MST_CONFIG_FILE="${TMP_DIR}/json-config.conf"
run_config_precedence_case "json" health
printf 'test_config.sh passed.\n'
