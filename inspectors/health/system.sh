#!/usr/bin/env bash
# System identity health collector.

# Read one key from /etc/os-release style files.
mst_health_read_os_release_key() {
    local file_path="${1:?file path required}"
    local key_name="${2:?key required}"
    local line value

    [[ -r "${file_path}" ]] || return 1
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ "${line}" == "${key_name}="* ]] || continue
        value="${line#*=}"
        value="${value%\"}"
        value="${value#\"}"
        printf '%s' "${value}"
        return 0
    done < "${file_path}"
    return 1
}

# Collect local system identity details.
mst_health_collect_system() {
    local record_name="${1:?record name required}"
    local details_name="${2:?details name required}"
    local errors_name="${3:?errors name required}"
    local rows_name="${4:?rows name required}"
    local -n record_ref="${record_name}"
    local started_ms hostname kernel architecture os_name os_version

    mst_health_init_data_sources
    started_ms="$(mst_mrrf_now_epoch_ms)"
    mst_health_record_init "${record_name}" "res_health.system_identity" "system_identity" "localhost" "procfs,filesystem,derived" "Derived from procfs kernel identity and os-release metadata."

    hostname="$(mst_health_detect_hostname)"
    kernel="$(mst_health_read_file "${MST_HEALTH_PROC_DIR}/sys/kernel/osrelease" 2>/dev/null | tr -d '\n' || true)"
    architecture="$(uname -m 2>/dev/null || printf 'unknown')"
    os_name="$(mst_health_read_os_release_key "${MST_HEALTH_OS_RELEASE_FILE}" "NAME" || printf 'unknown')"
    os_version="$(mst_health_read_os_release_key "${MST_HEALTH_OS_RELEASE_FILE}" "VERSION_ID" || printf 'unknown')"

    [[ -n "${hostname}" ]] || hostname="localhost"
    [[ -n "${kernel}" ]] || kernel="unknown"

    record_ref[status]="ok"
    record_ref[severity]="ok"
    record_ref[summary]="System identity is ${hostname} on ${os_name} ${os_version} with kernel ${kernel}."
    mst_health_add_detail "${details_name}" "hostname" "Hostname" "string" "${hostname}" "" "false"
    mst_health_add_detail "${details_name}" "kernel" "Kernel" "string" "${kernel}" "" "false"
    mst_health_add_detail "${details_name}" "architecture" "Architecture" "string" "${architecture}" "" "false"
    mst_health_add_detail "${details_name}" "operating_system" "Operating System" "string" "${os_name}" "" "false"
    mst_health_add_detail "${details_name}" "operating_system_version" "Operating System Version" "string" "${os_version}" "" "false"
    mst_health_add_row "${rows_name}" "Hostname" "${hostname}"
    mst_health_add_row "${rows_name}" "Kernel" "${kernel}"
    mst_health_add_row "${rows_name}" "Architecture" "${architecture}"
    mst_health_add_row "${rows_name}" "Operating System" "${os_name}"
    mst_health_add_row "${rows_name}" "OS Version" "${os_version}"
    mst_health_record_finalize "${record_name}" "${started_ms}"
}
