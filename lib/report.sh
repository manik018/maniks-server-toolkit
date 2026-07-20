#!/usr/bin/env bash
# Unified MRRF1 report aggregation helpers.

if [[ -n "${MST_REPORT_LIB_LOADED:-}" ]]; then
    return
fi
readonly MST_REPORT_LIB_LOADED=1

# Return the canonical module catalog as key|label|environment-variable rows.
mst_report_module_catalog() {
    cat <<'EOF'
health|Health|MST_HEALTH_REPORT_JSON
services|Services|MST_SERVICES_REPORT_JSON
security|Security|MST_SECURITY_REPORT_JSON
website|Websites|MST_WEBSITE_REPORT_JSON
wordpress|WordPress|MST_WORDPRESS_REPORT_JSON
backup|Backups|MST_BACKUP_REPORT_JSON
EOF
}

# Return success if the report engine knows one module key.
mst_report_known_module() {
    local module_key="${1:?module required}"
    local key _label _env_name
    while IFS='|' read -r key _label _env_name; do
        [[ "${key}" == "${module_key}" ]] && return 0
    done < <(mst_report_module_catalog)
    return 1
}

# Compact a JSON document to one line for the lightweight MRRF1 reader.
mst_report_compact_json() {
    tr -d '\n\r' <<< "${1:-}"
}

# Extract one top-level-ish JSON string field from MST-generated MRRF1 JSON.
mst_report_json_string_field() {
    local json_payload="${1:-}"
    local field_name="${2:?field required}"
    sed -n "s/.*\"${field_name}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" <<< "${json_payload}" | sed 's/\\"/"/g; s/\\\\/\\/g' | head -n 1
}

# Extract one JSON numeric field from MST-generated MRRF1 JSON.
mst_report_json_number_field() {
    local json_payload="${1:-}"
    local field_name="${2:?field required}"
    sed -n "s/.*\"${field_name}\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" <<< "${json_payload}" | head -n 1
}

# Extract a numeric detail value from one MST-generated compact record object.
mst_report_json_detail_number() {
    local record_json="${1:-}"
    local detail_key="${2:?key required}"
    sed -n "s/.*\"key\":\"${detail_key}\",\"label\":\"[^\"]*\",\"value_type\":\"[^\"]*\",\"value\":\\([0-9][0-9]*\\).*/\\1/p" <<< "${record_json}" | head -n 1
}

# Extract a string detail value from one MST-generated compact record object.
mst_report_json_detail_string() {
    local record_json="${1:-}"
    local detail_key="${2:?key required}"
    sed -n "s/.*\"key\":\"${detail_key}\",\"label\":\"[^\"]*\",\"value_type\":\"[^\"]*\",\"value\":\"\\([^\"]*\\)\".*/\\1/p" <<< "${record_json}" | sed 's/\\"/"/g; s/\\\\/\\/g' | head -n 1
}

# Return the records array payload from one aggregate report.
mst_report_records_payload() {
    local json_payload="${1:-}"
    sed -n 's/.*"records"[[:space:]]*:[[:space:]]*\[\(.*\)\][[:space:]]*,"aggregate".*/\1/p' <<< "${json_payload}"
}

# Split MST-generated record JSON objects onto separate lines.
mst_report_each_record_object() {
    local records_payload="${1:-}"
    [[ -n "${records_payload}" ]] || return 0
    sed 's/},{"result_id"/}\n{"result_id"/g' <<< "${records_payload}"
}

# Convert MRRF1 status to display bucket: ok, warn, critical, unavailable, unknown.
mst_report_normalize_status() {
    case "${1:-unknown}" in
        ok) printf 'ok' ;;
        warn) printf 'warn' ;;
        critical) printf 'critical' ;;
        unavailable) printf 'unavailable' ;;
        *) printf 'unknown' ;;
    esac
}

# Append one individual record row for terminal rendering.
mst_report_add_record_row() {
    local module_key="${1:?module required}"
    local target_name="${2:-module report}"
    local status_name="${3:-unknown}"
    local summary_text="${4:-No summary available.}"
    local check_name="${5:-}"
    local record_json="${6:-}"

    MST_REPORT_RECORD_ROWS+=("$(mst_mrrf_sanitize_text "${module_key}" 32)${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${target_name}" 48)${MST_MRRF_FIELD_SEPARATOR}$(mst_report_normalize_status "${status_name}")${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${summary_text}" 120)")
    MST_REPORT_RECORD_CHECKS+=("$(mst_mrrf_sanitize_text "${check_name}" 48)")
    MST_REPORT_RECORD_JSON+=("${record_json}")
}

# Append one module summary row for terminal rendering.
mst_report_add_module_summary() {
    local module_key="${1:?module required}"
    local label="${2:?label required}"
    local status_name="${3:?status required}"
    local ok_count="${4:?ok required}"
    local warn_count="${5:?warn required}"
    local critical_count="${6:?critical required}"
    local unavailable_count="${7:?unavailable required}"
    local unknown_count="${8:?unknown required}"
    local record_count="${9:?record count required}"

    MST_REPORT_MODULE_SUMMARIES+=("$(mst_mrrf_sanitize_text "${module_key}" 32)${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${label}" 32)${MST_MRRF_FIELD_SEPARATOR}$(mst_report_normalize_status "${status_name}")${MST_MRRF_FIELD_SEPARATOR}${ok_count}${MST_MRRF_FIELD_SEPARATOR}${warn_count}${MST_MRRF_FIELD_SEPARATOR}${critical_count}${MST_MRRF_FIELD_SEPARATOR}${unavailable_count}${MST_MRRF_FIELD_SEPARATOR}${unknown_count}${MST_MRRF_FIELD_SEPARATOR}${record_count}")
}

# Read supplied module=FILE arguments into environment-like report variables.
mst_report_load_argument_reports() {
    local arg module_key file_path env_name _label key label catalog_env

    for arg in "$@"; do
        [[ "${arg}" == *=* ]] || continue
        module_key="${arg%%=*}"
        file_path="${arg#*=}"
        mst_report_known_module "${module_key}" || continue
        [[ -f "${file_path}" ]] && [[ -r "${file_path}" ]] || continue
        while IFS='|' read -r key label catalog_env; do
            if [[ "${key}" == "${module_key}" ]]; then
                env_name="${catalog_env}"
                printf -v "${env_name}" '%s' "$(< "${file_path}")"
                export "${env_name}"
                break
            fi
        done < <(mst_report_module_catalog)
    done
}

# Return the JSON report configured for one module.
mst_report_json_for_env() {
    local env_name="${1:?env required}"
    local -n json_ref="${env_name}"
    printf '%s' "${json_ref:-}"
}

# Load persisted aggregate reports for every known module when no in-process value exists.
mst_report_load_persisted_reports() {
    local key _label env_name

    while IFS='|' read -r key _label env_name; do
        if [[ -z "$(mst_report_json_for_env "${env_name}")" ]]; then
            mst_state_load_report "${key}" "${env_name}" || true
        fi
    done < <(mst_report_module_catalog)
}

# Return success if one payload looks like a normalized MRRF1 aggregate report.
mst_report_validate_mrrf_report() {
    local module_key="${1:?module required}"
    local json_payload="${2:-}"
    local document_type command_name

    [[ -n "${json_payload}" ]] || return 1
    document_type="$(mst_report_json_string_field "${json_payload}" "document_type")"
    command_name="$(mst_report_json_string_field "${json_payload}" "command")"
    [[ "${document_type}" == "report" ]] || return 1
    [[ "${command_name}" == "${module_key}" ]] || return 1
    [[ "${json_payload}" == *'"records":['* ]] || return 1
    [[ "${json_payload}" == *'"aggregate":{'* ]] || return 1
}

# Add a synthetic unavailable section for a missing or invalid module report.
mst_report_add_unavailable_module() {
    local module_key="${1:?module required}"
    local label="${2:?label required}"
    local summary="${3:?summary required}"

    mst_report_add_record_row "${module_key}" "module report" "unavailable" "${summary}"
    mst_report_add_module_summary "${module_key}" "${label}" "unavailable" 0 0 0 1 0 1
    MST_REPORT_STATUS_VALUES+=("unavailable")
}

# Consume one MRRF1 aggregate report and add its section summary and record rows.
mst_report_consume_module_report() {
    local module_key="${1:?module required}"
    local label="${2:?label required}"
    local json_payload="${3:?json required}"
    local records_payload record_object target_name status_name summary_text check_name aggregate_status
    local ok_count=0 warn_count=0 critical_count=0 unavailable_count=0 unknown_count=0 record_count=0
    local normalized_status

    aggregate_status="$(mst_report_json_string_field "${json_payload}" "overall_status")"
    aggregate_status="$(mst_report_normalize_status "${aggregate_status}")"
    records_payload="$(mst_report_records_payload "${json_payload}")"

    while IFS= read -r record_object || [[ -n "${record_object}" ]]; do
        [[ -n "${record_object}" ]] || continue
        target_name="$(mst_report_json_string_field "${record_object}" "target")"
        status_name="$(mst_report_json_string_field "${record_object}" "status")"
        summary_text="$(mst_report_json_string_field "${record_object}" "summary")"
        check_name="$(mst_report_json_string_field "${record_object}" "check")"
        normalized_status="$(mst_report_normalize_status "${status_name}")"
        case "${normalized_status}" in
            ok) ok_count=$(( ok_count + 1 )) ;;
            warn) warn_count=$(( warn_count + 1 )) ;;
            critical) critical_count=$(( critical_count + 1 )) ;;
            unavailable) unavailable_count=$(( unavailable_count + 1 )) ;;
            *) unknown_count=$(( unknown_count + 1 )) ;;
        esac
        record_count=$(( record_count + 1 ))
        mst_report_add_record_row "${module_key}" "${target_name:-record}" "${normalized_status}" "${summary_text:-No summary available.}" "${check_name}" "${record_object}"
    done < <(mst_report_each_record_object "${records_payload}")

    if (( record_count == 0 )); then
        unknown_count=1
        record_count=1
        aggregate_status="unknown"
        mst_report_add_record_row "${module_key}" "module report" "unknown" "${label} report contained no records."
    fi

    mst_report_add_module_summary "${module_key}" "${label}" "${aggregate_status}" "${ok_count}" "${warn_count}" "${critical_count}" "${unavailable_count}" "${unknown_count}" "${record_count}"
    MST_REPORT_STATUS_VALUES+=("${aggregate_status}")
}

# Return the hostname embedded in one MRRF1 aggregate report, when present.
mst_report_hostname_from_report() {
    local json_payload="${1:-}"
    mst_report_json_string_field "${json_payload}" "hostname"
}

# Return the worst MRRF1 status from a status array.
mst_report_worst_status() {
    local array_name="${1:?array required}"
    local -n values_ref="${array_name}"
    local value worst_value="ok" current_rank worst_rank=0

    for value in "${values_ref[@]}"; do
        current_rank="$(mst_mrrf_status_rank "${value}")"
        worst_rank="$(mst_mrrf_status_rank "${worst_value}")"
        if (( current_rank > worst_rank )); then
            worst_value="${value}"
        fi
    done
    printf '%s' "${worst_value}"
}

# Return the report command exit code from aggregate statuses.
mst_report_exit_code() {
    local array_name="${1:?array required}"
    local -n values_ref="${array_name}"
    local value

    for value in "${values_ref[@]}"; do
        case "${value}" in
            warn|critical|unknown|unavailable)
                printf '%s' "${MST_EXIT_PARTIAL}"
                return 0
                ;;
        esac
    done
    printf '%s' "${MST_EXIT_OK}"
}

# Build a unified terminal-report model from existing MRRF1 aggregate reports.
mst_report_collect() {
    local key label env_name raw_json compact_json
    local total_modules=0 total_records=0 total_ok=0 total_warn=0 total_critical=0 total_unavailable=0 total_unknown=0
    local summary_row module_key _label status ok_count warn_count critical_count unavailable_count unknown_count record_count
    local report_hostname="unknown" candidate_hostname

    declare -ga MST_REPORT_MODULE_SUMMARIES=()
    declare -ga MST_REPORT_RECORD_ROWS=()
    declare -ga MST_REPORT_RECORD_CHECKS=()
    declare -ga MST_REPORT_RECORD_JSON=()
    declare -ga MST_REPORT_STATUS_VALUES=()

    mst_report_load_argument_reports "$@"
    mst_report_load_persisted_reports

    while IFS='|' read -r key label env_name; do
        total_modules=$(( total_modules + 1 ))
        raw_json="$(mst_report_json_for_env "${env_name}")"
        compact_json="$(mst_report_compact_json "${raw_json}")"
        if mst_report_validate_mrrf_report "${key}" "${compact_json}"; then
            candidate_hostname="$(mst_report_hostname_from_report "${compact_json}")"
            if [[ "${report_hostname}" == "unknown" ]] && [[ -n "${candidate_hostname}" ]]; then
                report_hostname="${candidate_hostname}"
            fi
            mst_report_consume_module_report "${key}" "${label}" "${compact_json}"
        else
            mst_report_add_unavailable_module "${key}" "${label}" "No normalized MRRF1 aggregate report was supplied for ${label}."
        fi
    done < <(mst_report_module_catalog)

    for summary_row in "${MST_REPORT_MODULE_SUMMARIES[@]}"; do
        IFS="${MST_MRRF_FIELD_SEPARATOR}" read -r module_key _label status ok_count warn_count critical_count unavailable_count unknown_count record_count <<< "${summary_row}"
        total_ok=$(( total_ok + ok_count ))
        total_warn=$(( total_warn + warn_count ))
        total_critical=$(( total_critical + critical_count ))
        total_unavailable=$(( total_unavailable + unavailable_count ))
        total_unknown=$(( total_unknown + unknown_count ))
        total_records=$(( total_records + record_count ))
    done

    export MST_REPORT_HOSTNAME="${report_hostname}"
    export MST_REPORT_TIMESTAMP="$(mst_mrrf_now_utc)"
    export MST_REPORT_STATUS="$(mst_report_worst_status MST_REPORT_STATUS_VALUES)"
    case "${MST_REPORT_STATUS}" in
        ok) export MST_REPORT_OVERALL="HEALTHY" ;;
        warn) export MST_REPORT_OVERALL="WARNING" ;;
        critical) export MST_REPORT_OVERALL="CRITICAL" ;;
        *) export MST_REPORT_OVERALL="ATTENTION" ;;
    esac
    export MST_REPORT_TOTAL_MODULES="${total_modules}"
    export MST_REPORT_TOTAL_RECORDS="${total_records}"
    export MST_REPORT_TOTAL_OK="${total_ok}"
    export MST_REPORT_TOTAL_WARN="${total_warn}"
    export MST_REPORT_TOTAL_CRITICAL="${total_critical}"
    export MST_REPORT_TOTAL_UNAVAILABLE="${total_unavailable}"
    export MST_REPORT_TOTAL_UNKNOWN="${total_unknown}"
    export MST_REPORT_EXIT_CODE="$(mst_report_exit_code MST_REPORT_STATUS_VALUES)"
}
