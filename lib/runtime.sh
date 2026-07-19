#!/usr/bin/env bash
# MST runtime constants and process helpers.

readonly MST_APP_NAME="Manik's Server Toolkit"
readonly MST_PROGRAM_NAME="mst"
readonly MST_VERSION="0.1.0-foundation"
readonly MST_SUPPORTED_CONFIG_SCHEMA_VERSION="1"
readonly MST_DEFAULT_TIMEOUT_SECONDS="10"
readonly MST_LOCK_SCHEMA_VERSION="1"

# Initialize the process environment before config is loaded.
mst_runtime_init() {
    umask 027

    export MST_COLOR_MODE="${MST_COLOR_MODE:-auto}"
    export MST_OUTPUT_MODE="${MST_OUTPUT_MODE:-text}"
    export MST_TIMEOUT_SECONDS="${MST_TIMEOUT_SECONDS:-${MST_DEFAULT_TIMEOUT_SECONDS}}"
    export MST_VERBOSE="${MST_VERBOSE:-0}"
    export MST_QUIET="${MST_QUIET:-0}"
    export MST_LOG_DIR="/var/log/mst"
    export MST_STATE_DIR="/var/lib/mst"
    export MST_LOCK_DIR="${MST_STATE_DIR}/locks"
    unset MST_LOG_FILE
}

# Apply parsed global CLI options to the runtime.
mst_apply_global_cli_options() {
    if [[ -n "${MST_GLOBAL_OUTPUT_MODE:-}" ]]; then
        export MST_OUTPUT_MODE="${MST_GLOBAL_OUTPUT_MODE}"
    fi

    if [[ -n "${MST_GLOBAL_TIMEOUT:-}" ]]; then
        export MST_TIMEOUT_SECONDS="${MST_GLOBAL_TIMEOUT}"
    fi

    if [[ "${MST_GLOBAL_VERBOSE:-0}" -eq 1 ]]; then
        export MST_VERBOSE=1
    fi

    if [[ "${MST_GLOBAL_QUIET:-0}" -eq 1 ]]; then
        export MST_QUIET=1
    fi

    if [[ "${MST_GLOBAL_NO_COLOR:-0}" -eq 1 ]]; then
        export MST_COLOR_MODE="never"
    fi

    if [[ -n "${MST_GLOBAL_CONFIG_FILE:-}" ]]; then
        export MST_CONFIG_FILE="${MST_GLOBAL_CONFIG_FILE}"
    fi
}

# Return a stable run identifier for logs and locks.
mst_make_run_id() {
    printf 'run_%s_%s' "$(date -u '+%Y%m%dT%H%M%SZ')" "$$"
}

# Print the canonical version string.
mst_version_string() {
    printf '%s %s' "${MST_APP_NAME}" "${MST_VERSION}"
}

# Return the canonical lock file path for a logical command name.
mst_lock_file_path() {
    local lock_name="${1:?lock name required}"
    printf '%s/%s.lock' "${MST_LOCK_DIR}" "${lock_name}"
}

# Sanitize a bounded metadata value for lock diagnostics.
mst_lock_sanitize_metadata_value() {
    local value="${1:-}"
    value="${value//\\/}"
    value="${value//\"/}"
    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\t'/ }"
    printf '%.64s' "${value}"
}

# Return the canonical lock metadata path for a logical command name.
mst_lock_metadata_path() {
    local lock_name="${1:?lock name required}"
    printf '%s/%s.lock.json' "${MST_LOCK_DIR}" "${lock_name}"
}

# Create the lock directory if it is missing.
mst_lock_prepare_directory() {
    MST_LOCK_DIR="$(mst_fs_validate_runtime_directory "${MST_LOCK_DIR}")" || return 1
    mkdir -p -- "${MST_LOCK_DIR}"
    chmod 0750 "${MST_LOCK_DIR}" 2>/dev/null || true
}

# Acquire a non-blocking flock for a logical command name.
mst_lock_acquire_nonblocking() {
    local lock_name="${1:?lock name required}"
    local lock_path

    mst_lock_prepare_directory || return 1
    lock_path="$(mst_lock_file_path "${lock_name}")"
    if [[ -L "${lock_path}" ]]; then
        return 1
    fi

    exec {MST_LOCK_FD}>"${lock_path}"
    if flock -n "${MST_LOCK_FD}"; then
        chmod 0640 "${lock_path}" 2>/dev/null || true
        export MST_ACTIVE_LOCK_NAME="${lock_name}"
        export MST_ACTIVE_LOCK_PATH="${lock_path}"
        export MST_ACTIVE_LOCK_FD="${MST_LOCK_FD}"
        return 0
    fi

    exec {MST_LOCK_FD}>&-
    unset MST_LOCK_FD
    return 1
}

# Write diagnostic metadata for an already-held lock.
mst_lock_write_metadata() {
    local trigger="${1:?trigger required}"
    local metadata_path tmp_file username
    [[ -n "${MST_ACTIVE_LOCK_NAME:-}" ]] || return 1

    metadata_path="$(mst_lock_metadata_path "${MST_ACTIVE_LOCK_NAME}")"
    metadata_path="$(mst_fs_validate_runtime_file_path "${metadata_path}")" || return 1
    if [[ -L "${metadata_path}" ]]; then
        return 1
    fi

    username="$(mst_lock_sanitize_metadata_value "$(id -un 2>/dev/null || printf 'unknown')")"
    tmp_file="$(mktemp "${metadata_path}.tmp.XXXXXX")"
    trap 'rm -f -- "${tmp_file}"' RETURN
    cat > "${tmp_file}" <<EOF
{
  "schema_version": ${MST_LOCK_SCHEMA_VERSION},
  "run_id": "$(mst_make_run_id)",
  "pid": $$,
  "uid": ${EUID},
  "username": "${username}",
  "command": "$(mst_lock_sanitize_metadata_value "${MST_ACTIVE_LOCK_NAME}")",
  "trigger": "$(mst_lock_sanitize_metadata_value "${trigger}")",
  "hostname": "$(mst_lock_sanitize_metadata_value "$(hostname 2>/dev/null || printf 'unknown')")",
  "started_at": "$(date -u '+%Y-%m-%dT%H:%M:%SZ')",
  "toolkit_version": "$(mst_lock_sanitize_metadata_value "${MST_VERSION}")"
}
EOF
    chmod 0640 "${tmp_file}" 2>/dev/null || true
    mv -f -- "${tmp_file}" "${metadata_path}"
    trap - RETURN
}

# Release an active lock if one is held.
mst_lock_release() {
    if [[ -n "${MST_ACTIVE_LOCK_FD:-}" ]]; then
        flock -u "${MST_ACTIVE_LOCK_FD}" || true
        exec {MST_ACTIVE_LOCK_FD}>&-
        unset MST_ACTIVE_LOCK_FD MST_ACTIVE_LOCK_NAME MST_ACTIVE_LOCK_PATH
    fi
}

# Run one top-level command while holding its existing non-blocking runtime lock.
mst_command_run_with_lock() {
    local lock_name="${1:?lock name required}"
    local function_name="${2:?function required}"
    shift 2 || true
    local command_exit

    if ! mst_lock_acquire_nonblocking "${lock_name}"; then
        mst_warning_block "Another ${lock_name} execution is already running."
        return "${MST_EXIT_PARTIAL}"
    fi

    mst_lock_write_metadata "manual" || true
    if "${function_name}" "$@"; then
        command_exit="${MST_EXIT_OK}"
    else
        command_exit=$?
    fi
    mst_lock_release
    return "${command_exit}"
}
