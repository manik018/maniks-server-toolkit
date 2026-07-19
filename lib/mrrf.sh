#!/usr/bin/env bash
# MST MRRF1 serialization helpers.

readonly MST_MRRF_FIELD_SEPARATOR=$'\x1f'

# Return the current UTC timestamp in RFC 3339 format.
mst_mrrf_now_utc() {
    date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# Return the current UTC time in milliseconds since epoch.
mst_mrrf_now_epoch_ms() {
    date -u '+%s%3N'
}

# Remove control characters and bound text length for MRRF1 fields.
mst_mrrf_sanitize_text() {
    local value="${1:-}"
    local max_length="${2:-200}"

    value="${value//$'\n'/ }"
    value="${value//$'\r'/ }"
    value="${value//$'\t'/ }"
    value="${value//\\/\\\\}"
    printf "%.${max_length}s" "${value}"
}

# Escape a string for safe JSON embedding.
mst_mrrf_json_escape() {
    local value="${1:-}"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\b'/\\b}"
    value="${value//$'\f'/\\f}"
    value="${value//$'\n'/\\n}"
    value="${value//$'\r'/\\r}"
    value="${value//$'\t'/\\t}"
    printf '%s' "${value}"
}

# Pack one MRRF1 detail object into a shell-safe field string.
mst_mrrf_pack_detail() {
    printf '%s' "$(mst_mrrf_sanitize_text "${1:-}" 64)${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${2:-}" 64)${MST_MRRF_FIELD_SEPARATOR}${3:-string}${MST_MRRF_FIELD_SEPARATOR}${4:-}${MST_MRRF_FIELD_SEPARATOR}${5:-}${MST_MRRF_FIELD_SEPARATOR}${6:-false}"
}

# Pack one MRRF1 error object into a shell-safe field string.
mst_mrrf_pack_error() {
    printf '%s' "${1:-unknown}${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${2:-UNKNOWN}" 64)${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${3:-Unknown error}" 200)"
}

# Convert one packed detail entry to JSON.
mst_mrrf_detail_json() {
    local packed="${1:?packed detail required}"
    local key label value_type value unit redacted

    IFS="${MST_MRRF_FIELD_SEPARATOR}" read -r key label value_type value unit redacted <<< "${packed}"
    case "${value_type}" in
        integer|number|boolean|null)
            ;;
        *)
            value_type="string"
            ;;
    esac

    case "${value_type}" in
        integer|number)
            value="${value:-0}"
            ;;
        boolean)
            value="${value:-false}"
            ;;
        null)
            value="null"
            ;;
        string)
            value="\"$(mst_mrrf_json_escape "$(mst_mrrf_sanitize_text "${value}" 256)")\""
            ;;
    esac

    printf '{"key":"%s","label":"%s","value_type":"%s","value":%s,"unit":"%s","redacted":%s}' \
        "$(mst_mrrf_json_escape "${key}")" \
        "$(mst_mrrf_json_escape "${label}")" \
        "${value_type}" \
        "${value}" \
        "$(mst_mrrf_json_escape "${unit}")" \
        "${redacted:-false}"
}

# Convert one packed error entry to JSON.
mst_mrrf_error_json() {
    local packed="${1:?packed error required}"
    local category code message

    IFS="${MST_MRRF_FIELD_SEPARATOR}" read -r category code message <<< "${packed}"
    printf '{"category":"%s","code":"%s","message":"%s"}' \
        "$(mst_mrrf_json_escape "${category}")" \
        "$(mst_mrrf_json_escape "${code}")" \
        "$(mst_mrrf_json_escape "${message}")"
}

# Convert one result record to JSON.
mst_mrrf_record_json() {
    local record_name="${1:?record name required}"
    local details_name="${2:?details array name required}"
    local errors_name="${3:?errors array name required}"
    local -n record_ref="${record_name}"
    local -n details_ref="${details_name}"
    local -n errors_ref="${errors_name}"
    local details_json=()
    local errors_json=()
    local packed source_entry
    local source_json=()
    local score_json

    for packed in "${details_ref[@]}"; do
        details_json+=("$(mst_mrrf_detail_json "${packed}")")
    done

    for packed in "${errors_ref[@]}"; do
        errors_json+=("$(mst_mrrf_error_json "${packed}")")
    done

    IFS=',' read -r -a source_entries <<< "${record_ref[source_list]:-unknown}"
    for source_entry in "${source_entries[@]}"; do
        [[ -n "${source_entry}" ]] || continue
        source_json+=("\"$(mst_mrrf_json_escape "${source_entry}")\"")
    done
    [[ "${#source_json[@]}" -gt 0 ]] || source_json+=("\"unknown\"")

    if [[ -n "${record_ref[score]:-}" ]] && [[ "${record_ref[score]}" != "null" ]]; then
        score_json="${record_ref[score]}"
    else
        score_json="null"
    fi

    printf '{"result_id":"%s","module":"%s","check":"%s","target":"%s","status":"%s","severity":"%s","score":%s,"summary":"%s","details":[%s],"recommendations":[],"metadata":{"source":[%s],"provenance":"%s","privilege_requirement":"%s","contains_sensitive_data":false,"redactions_present":%s,"optional_dependencies":[]},"errors":[%s],"duration_ms":%s,"observed_at":"%s"}' \
        "$(mst_mrrf_json_escape "${record_ref[result_id]}")" \
        "$(mst_mrrf_json_escape "${record_ref[module]}")" \
        "$(mst_mrrf_json_escape "${record_ref[check]}")" \
        "$(mst_mrrf_json_escape "${record_ref[target]}")" \
        "$(mst_mrrf_json_escape "${record_ref[status]}")" \
        "$(mst_mrrf_json_escape "${record_ref[severity]}")" \
        "${score_json}" \
        "$(mst_mrrf_json_escape "$(mst_mrrf_sanitize_text "${record_ref[summary]}" 200)")" \
        "$(IFS=,; printf '%s' "${details_json[*]:-}")" \
        "$(IFS=,; printf '%s' "${source_json[*]:-}")" \
        "$(mst_mrrf_json_escape "$(mst_mrrf_sanitize_text "${record_ref[provenance]}" 200)")" \
        "$(mst_mrrf_json_escape "${record_ref[privilege_requirement]:-none}")" \
        "${record_ref[redactions_present]:-false}" \
        "$(IFS=,; printf '%s' "${errors_json[*]:-}")" \
        "${record_ref[duration_ms]:-0}" \
        "$(mst_mrrf_json_escape "${record_ref[observed_at]}")"
}

# Return the severity rank for a record status.
mst_mrrf_status_rank() {
    case "${1:-unknown}" in
        critical) printf '4' ;;
        unavailable) printf '3' ;;
        unknown) printf '2' ;;
        warn) printf '1' ;;
        ok) printf '0' ;;
        skipped) printf '-1' ;;
        *) printf '2' ;;
    esac
}

# Return the risk level for an aggregate status.
mst_mrrf_risk_level_for_status() {
    case "${1:-unknown}" in
        ok) printf 'low' ;;
        warn) printf 'medium' ;;
        critical) printf 'high' ;;
        *) printf 'unknown' ;;
    esac
}
