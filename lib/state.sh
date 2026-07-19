#!/usr/bin/env bash
# Persist and load MRRF1 aggregate reports in the MST runtime state directory.

if [[ -n "${MST_STATE_LIB_LOADED:-}" ]]; then
    return
fi
readonly MST_STATE_LIB_LOADED=1

mst_state_report_path() {
    local module_key="${1:?module required}"

    [[ -n "${MST_STATE_DIR:-}" ]] || return 1
    case "${module_key}" in
        health)
            printf '%s/reports/%s.mrrf1.json' "${MST_STATE_DIR:?state dir required}" "${module_key}"
            ;;
        *)
            return 1
            ;;
    esac
}

mst_state_save_report() {
    local module_key="${1:?module required}"
    (($# >= 2)) || return 1
    local report_json="${2}"
    local report_file report_dir

    report_file="$(mst_state_report_path "${module_key}")" || return 1
    report_dir="$(dirname -- "${report_file}")"
    report_dir="$(mst_fs_validate_runtime_directory "${report_dir}")" || return 1
    mst_fs_ensure_directory "${report_dir}" || return 1
    report_file="$(mst_fs_validate_runtime_file_path "${report_file}")" || return 1
    mst_fs_atomic_write "${report_file}" 0660 "${report_json}"
}

mst_state_load_report() {
    local module_key="${1:?module required}"
    local env_name="${2:?env required}"
    local report_file

    report_file="$(mst_state_report_path "${module_key}")" || return 1
    [[ -e "${report_file}" ]] || return 0
    report_file="$(mst_fs_validate_runtime_file_path "${report_file}")" || return 1
    [[ -f "${report_file}" ]] && [[ -r "${report_file}" ]] || return 1
    printf -v "${env_name}" '%s' "$(< "${report_file}")"
    export "${env_name}"
}
