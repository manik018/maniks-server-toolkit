#!/usr/bin/env bash
# MST filesystem safety helpers.

# Return success if the path exists and is a symlink.
mst_fs_is_symlink() {
    [[ -L "${1:-}" ]]
}

# Return a canonical path if it can be resolved safely.
mst_fs_canonical_path() {
    local path="${1:-}"
    [[ -n "${path}" ]] || return 1
    readlink -f -- "${path}"
}

# Return a canonical path for a file target, resolving its parent directory.
mst_fs_canonical_target_path() {
    local path="${1:?path required}"
    local base_name canonical_parent

    if [[ -e "${path}" ]] || [[ -L "${path}" ]]; then
        mst_fs_canonical_path "${path}"
        return $?
    fi

    base_name="$(basename -- "${path}")"
    canonical_parent="$(mst_fs_canonical_directory_target "$(dirname -- "${path}")")" || return 1
    printf '%s/%s' "${canonical_parent}" "${base_name}"
}

# Return a canonical path for a directory target, resolving the nearest existing parent.
mst_fs_canonical_directory_target() {
    local path="${1:?path required}"
    local current_path missing_parts=()
    local canonical_parent

    if [[ -e "${path}" ]] || [[ -L "${path}" ]]; then
        mst_fs_canonical_path "${path}"
        return $?
    fi

    current_path="${path}"
    while [[ ! -e "${current_path}" ]] && [[ ! -L "${current_path}" ]]; do
        missing_parts+=("$(basename -- "${current_path}")")
        current_path="$(dirname -- "${current_path}")"
        [[ "${current_path}" != "." ]] || return 1
    done

    [[ ! -L "${current_path}" ]] || return 1

    canonical_parent="$(mst_fs_canonical_path "${current_path}")" || return 1
    while ((${#missing_parts[@]} > 0)); do
        canonical_parent="${canonical_parent}/$(printf '%s' "${missing_parts[-1]}")"
        unset 'missing_parts[-1]'
    done
    printf '%s' "${canonical_parent}"
}

# Return the numeric owner uid for a filesystem path.
mst_fs_path_owner_uid() {
    stat -c '%u' -- "${1:?path required}"
}

# Return the numeric mode bits for a filesystem path.
mst_fs_path_mode_octal() {
    stat -c '%a' -- "${1:?path required}"
}

# Return success if the path is owned by root or the current effective user.
mst_fs_is_safe_owner_uid() {
    local owner_uid="${1:?owner uid required}"
    [[ "${owner_uid}" == "0" ]] || [[ "${owner_uid}" == "${EUID}" ]]
}

# Return success if the path is writable by group or other users.
mst_fs_is_group_or_other_writable() {
    local mode="${1:?mode required}"
    local group_digit other_digit

    group_digit="${mode: -2:1}"
    other_digit="${mode: -1}"
    (( (10#${group_digit} & 2) != 0 )) || (( (10#${other_digit} & 2) != 0 ))
}

# Return success if the path is writable by other users.
mst_fs_is_world_writable() {
    local mode="${1:?mode required}"
    local other_digit

    other_digit="${mode: -1}"
    (( (10#${other_digit} & 2) != 0 ))
}

# Return success if the path exists and is a regular file.
mst_fs_is_regular_file() {
    [[ -f "${1:-}" ]] && [[ ! -L "${1:-}" ]]
}

# Return success if the path exists and is a directory.
mst_fs_is_directory() {
    [[ -d "${1:-}" ]] && [[ ! -L "${1:-}" ]]
}

# Return success if the directory can be created or already exists.
mst_fs_ensure_directory() {
    local path="${1:?path required}"
    mkdir -p -- "${path}"
}

# Validate an MST-owned runtime directory and print its canonical path.
mst_fs_validate_runtime_directory() {
    local path="${1:?path required}"
    local canonical_path existing_path mode owner_uid

    [[ ! -L "${path}" ]] || return 1

    canonical_path="$(mst_fs_canonical_directory_target "${path}")" || return 1
    mst_validate_mst_owned_path "${canonical_path}" || return 1

    existing_path="${canonical_path}"
    while [[ ! -e "${existing_path}" ]] && [[ ! -L "${existing_path}" ]]; do
        existing_path="$(dirname -- "${existing_path}")"
    done

    mst_fs_is_directory "${existing_path}" || return 1
    owner_uid="$(mst_fs_path_owner_uid "${existing_path}")" || return 1
    mst_fs_is_safe_owner_uid "${owner_uid}" || return 1
    mode="$(mst_fs_path_mode_octal "${existing_path}")" || return 1
    if mst_fs_is_world_writable "${mode}"; then
        return 1
    fi

    printf '%s' "${canonical_path}"
}

# Validate an MST-owned runtime file path and print its canonical path.
mst_fs_validate_runtime_file_path() {
    local path="${1:?path required}"
    local canonical_path parent_path owner_uid mode

    [[ ! -L "${path}" ]] || return 1

    canonical_path="$(mst_fs_canonical_target_path "${path}")" || return 1
    mst_validate_mst_owned_path "${canonical_path}" || return 1
    parent_path="$(dirname -- "${canonical_path}")"
    parent_path="$(mst_fs_validate_runtime_directory "${parent_path}")" || return 1

    if [[ -e "${canonical_path}" ]] || [[ -L "${canonical_path}" ]]; then
        mst_fs_is_regular_file "${canonical_path}" || return 1
        owner_uid="$(mst_fs_path_owner_uid "${canonical_path}")" || return 1
        mst_fs_is_safe_owner_uid "${owner_uid}" || return 1
        mode="$(mst_fs_path_mode_octal "${canonical_path}")" || return 1
        if mst_fs_is_world_writable "${mode}"; then
            return 1
        fi
    fi

    printf '%s' "${canonical_path}"
}

# Validate a trusted configuration file before parsing it.
mst_fs_validate_trusted_config_file() {
    local path="${1:?path required}"
    local canonical_path parent_path owner_uid mode parent_owner parent_mode

    mst_fs_is_regular_file "${path}" || return 1
    canonical_path="$(mst_fs_canonical_path "${path}")" || return 1
    [[ "${canonical_path}" == "${path}" ]] || return 1

    parent_path="$(dirname -- "${canonical_path}")"
    mst_fs_is_directory "${parent_path}" || return 1

    owner_uid="$(mst_fs_path_owner_uid "${canonical_path}")" || return 1
    mst_fs_is_safe_owner_uid "${owner_uid}" || return 1
    mode="$(mst_fs_path_mode_octal "${canonical_path}")" || return 1
    if mst_fs_is_group_or_other_writable "${mode}"; then
        return 1
    fi

    parent_owner="$(mst_fs_path_owner_uid "${parent_path}")" || return 1
    mst_fs_is_safe_owner_uid "${parent_owner}" || return 1
    parent_mode="$(mst_fs_path_mode_octal "${parent_path}")" || return 1
    if mst_fs_is_group_or_other_writable "${parent_mode}"; then
        return 1
    fi

    return 0
}

# Validate all runtime write destinations and canonicalize them in place.
mst_fs_validate_runtime_write_paths() {
    local canonical_log_dir canonical_state_dir canonical_lock_dir canonical_log_file

    canonical_log_dir="$(mst_fs_validate_runtime_directory "${MST_LOG_DIR:?log dir required}")" || return 1
    canonical_state_dir="$(mst_fs_validate_runtime_directory "${MST_STATE_DIR:?state dir required}")" || return 1
    canonical_lock_dir="$(mst_fs_validate_runtime_directory "${MST_LOCK_DIR:?lock dir required}")" || return 1
    canonical_log_file="$(mst_fs_validate_runtime_file_path "${canonical_log_dir}/mst.log")" || return 1

    export MST_LOG_DIR="${canonical_log_dir}"
    export MST_STATE_DIR="${canonical_state_dir}"
    export MST_LOCK_DIR="${canonical_lock_dir}"
    export MST_LOG_FILE="${canonical_log_file}"
}

# Write a file atomically without following symlinks.
mst_fs_atomic_write() {
    local target="${1:?target required}"
    local mode="${2:?mode required}"
    (($# >= 3)) || {
        printf 'content required\n' >&2
        return 1
    }
    local content="${3}"
    local target_dir tmp_file

    if mst_fs_is_symlink "${target}"; then
        return 1
    fi

    target_dir="$(dirname "${target}")"
    mst_fs_ensure_directory "${target_dir}"
    tmp_file="$(mktemp "${target}.tmp.XXXXXX")"
    trap 'rm -f -- "${tmp_file}"' RETURN
    printf '%s\n' "${content}" > "${tmp_file}"
    if declare -F mst_runtime_normalize_write_file >/dev/null 2>&1; then
        mst_runtime_normalize_write_file "${tmp_file}" "${mode}"
    else
        chmod "${mode}" "${tmp_file}"
    fi
    mv -f -- "${tmp_file}" "${target}"
    trap - RETURN
}
