#!/usr/bin/env bash
# Alert policy evaluation over existing MRRF1 aggregate reports.

if [[ -n "${MST_ALERT_LIB_LOADED:-}" ]]; then
    return
fi
readonly MST_ALERT_LIB_LOADED=1

# Return supported alert modules as key|environment-variable rows.
mst_alert_module_catalog() {
    cat <<'EOF'
health|MST_HEALTH_REPORT_JSON
services|MST_SERVICES_REPORT_JSON
security|MST_SECURITY_REPORT_JSON
website|MST_WEBSITE_REPORT_JSON
wordpress|MST_WORDPRESS_REPORT_JSON
backup|MST_BACKUP_REPORT_JSON
EOF
}

# Return current alert epoch seconds, overridable for tests.
mst_alert_now_epoch() {
    if [[ -n "${MST_ALERT_TEST_NOW_EPOCH:-}" ]]; then
        printf '%s' "${MST_ALERT_TEST_NOW_EPOCH}"
    else
        date -u '+%s'
    fi
}

# Return current alert timestamp.
mst_alert_now_utc() {
    local epoch_value
    epoch_value="$(mst_alert_now_epoch)"
    date -u -d "@${epoch_value}" '+%Y-%m-%dT%H:%M:%SZ'
}

# Compact JSON to one line for the lightweight MRRF1 reader.
mst_alert_compact_json() {
    tr -d '\n\r' <<< "${1:-}"
}

# Extract a simple JSON string field from MST-generated MRRF1 JSON.
mst_alert_json_string_field() {
    local json_payload="${1:-}"
    local field_name="${2:?field required}"
    sed -n "s/.*\"${field_name}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" <<< "${json_payload}" | sed 's/\\"/"/g; s/\\\\/\\/g' | head -n 1
}

# Return the records array payload from one aggregate report.
mst_alert_records_payload() {
    local json_payload="${1:-}"
    sed -n 's/.*"records"[[:space:]]*:[[:space:]]*\[\(.*\)\][[:space:]]*,"aggregate".*/\1/p' <<< "${json_payload}"
}

# Split MST-generated record JSON objects onto separate lines.
mst_alert_each_record_object() {
    local records_payload="${1:-}"
    [[ -n "${records_payload}" ]] || return 0
    sed 's/},{"result_id"/}\n{"result_id"/g' <<< "${records_payload}"
}

# Return normalized MRRF1 status.
mst_alert_normalize_status() {
    case "${1:-unknown}" in
        ok) printf 'ok' ;;
        warn) printf 'warn' ;;
        critical) printf 'critical' ;;
        unavailable) printf 'unavailable' ;;
        unknown) printf 'unknown' ;;
        *) printf 'unknown' ;;
    esac
}

# Return display status for alert terminal output.
mst_alert_status_label() {
    case "${1:-unknown}" in
        ok) printf 'SUCCESS' ;;
        warn) printf 'WARNING' ;;
        critical) printf 'ERROR' ;;
        unavailable) printf 'UNAVAILABLE' ;;
        *) printf 'UNKNOWN' ;;
    esac
}

# Return success if one normalized status is configured to alert.
mst_alert_policy_enabled_for_status() {
    case "${1:-unknown}" in
        warn) [[ "$(mst_alert_bool "${MST_ALERT_ON_WARNING:-true}")" == "true" ]] ;;
        critical) [[ "$(mst_alert_bool "${MST_ALERT_ON_ERROR:-true}")" == "true" ]] ;;
        unavailable) [[ "$(mst_alert_bool "${MST_ALERT_ON_UNAVAILABLE:-true}")" == "true" ]] ;;
        unknown) [[ "$(mst_alert_bool "${MST_ALERT_ON_UNKNOWN:-true}")" == "true" ]] ;;
        *) return 1 ;;
    esac
}

# Normalize boolean-like flags without depending on delivery modules.
mst_alert_bool() {
    case "${1:-}" in
        1|yes|true) printf 'true' ;;
        *) printf 'false' ;;
    esac
}

# Return success if one module is enabled by the module filter.
mst_alert_module_enabled() {
    local module_name="${1:?module required}"
    local configured="${MST_ALERT_MODULES:-all}"
    local item

    [[ "${configured}" == "all" ]] && return 0
    IFS=',' read -r -a alert_modules <<< "${configured}"
    for item in "${alert_modules[@]}"; do
        [[ "${item}" == "${module_name}" ]] && return 0
    done
    return 1
}

# Return success if one module is supported.
mst_alert_known_module() {
    local module_name="${1:?module required}"
    local key _env
    while IFS='|' read -r key _env; do
        [[ "${key}" == "${module_name}" ]] && return 0
    done < <(mst_alert_module_catalog)
    return 1
}

# Load module=FILE arguments into the existing report environment variables.
mst_alert_load_argument_reports() {
    local arg module_name file_path key env_name

    for arg in "$@"; do
        [[ "${arg}" == *=* ]] || continue
        module_name="${arg%%=*}"
        file_path="${arg#*=}"
        mst_alert_known_module "${module_name}" || {
            mst_alert_add_event "invalid.${module_name}" "${module_name}" "input" "unknown" "" "SUPPRESSED" "" "" "0" "unsupported_module" "Unsupported alert module input: ${module_name}" "false" "true" "unsupported_module" "false"
            continue
        }
        [[ -f "${file_path}" ]] && [[ ! -L "${file_path}" ]] && [[ -r "${file_path}" ]] || {
            mst_alert_add_event "invalid.${module_name}" "${module_name}" "input" "unknown" "" "SUPPRESSED" "" "" "0" "invalid_input_file" "Alert input file is missing or unsafe for ${module_name}" "false" "true" "invalid_input_file" "false"
            continue
        }
        while IFS='|' read -r key env_name; do
            if [[ "${key}" == "${module_name}" ]]; then
                printf -v "${env_name}" '%s' "$(< "${file_path}")"
                export "${env_name}"
                break
            fi
        done < <(mst_alert_module_catalog)
    done
}

# Return the JSON report configured for one module environment variable.
mst_alert_json_for_env() {
    local env_name="${1:?env required}"
    local -n json_ref="${env_name}"
    printf '%s' "${json_ref:-}"
}

# Load persisted aggregate reports for every alert module when no in-process value exists.
mst_alert_load_persisted_reports() {
    local key env_name

    while IFS='|' read -r key env_name; do
        if [[ -z "$(mst_alert_json_for_env "${env_name}")" ]]; then
            mst_state_load_report "${key}" "${env_name}" || true
        fi
    done < <(mst_alert_module_catalog)
}

# Validate the outer MRRF1 report shape.
mst_alert_validate_mrrf_report() {
    local module_name="${1:?module required}"
    local json_payload="${2:-}"
    local document_type command_name

    [[ -n "${json_payload}" ]] || return 1
    document_type="$(mst_alert_json_string_field "${json_payload}" "document_type")"
    command_name="$(mst_alert_json_string_field "${json_payload}" "command")"
    [[ "${document_type}" == "report" ]] || return 1
    [[ "${command_name}" == "${module_name}" ]] || return 1
    [[ "${json_payload}" == *'"records":['* ]] || return 1
    [[ "${json_payload}" == *'"aggregate":{'* ]] || return 1
}

# Return stable identifier suffix from arbitrary record text.
mst_alert_sanitize_id() {
    local value="${1:-record}"
    value="$(printf '%s' "${value}" | tr '[:upper:]' '[:lower:]')"
    value="$(printf '%s' "${value}" | tr -cs 'a-z0-9_.-' '_')"
    value="${value##_}"
    value="${value%%_}"
    printf '%s' "${value:-record}"
}

# Return deterministic event id.
mst_alert_event_id() {
    local module_name="${1:?module required}"
    local record_id="${2:?record required}"
    printf 'alert.%s.%s' "$(mst_alert_sanitize_id "${module_name}")" "$(mst_alert_sanitize_id "${record_id}")"
}

# Return the approved alert state file path.
mst_alert_state_file_path() {
    local state_dir
    state_dir="$(mst_fs_validate_runtime_directory "${MST_STATE_DIR:?state dir required}")" || return 1
    printf '%s/alerts.state' "${state_dir}"
}

# Classify the alert state target without following unsafe replacement paths.
mst_alert_state_target_kind() {
    local state_file="${1:?state file required}"

    [[ -e "${state_file}" ]] || [[ -L "${state_file}" ]] || {
        printf 'missing'
        return 0
    }
    [[ ! -L "${state_file}" ]] || {
        printf 'symlink'
        return 0
    }
    [[ ! -d "${state_file}" ]] || {
        printf 'directory'
        return 0
    }
    [[ ! -p "${state_file}" ]] || {
        printf 'fifo'
        return 0
    }
    [[ ! -S "${state_file}" ]] || {
        printf 'socket'
        return 0
    }
    [[ ! -b "${state_file}" ]] || {
        printf 'block_device'
        return 0
    }
    [[ ! -c "${state_file}" ]] || {
        printf 'character_device'
        return 0
    }
    [[ ! -f "${state_file}" ]] || {
        printf 'regular'
        return 0
    }
    printf 'special'
}

# Validate whether alert state can be loaded and persisted.
mst_alert_prepare_state_target() {
    local state_file="${1:?state file required}"
    local target_kind

    export MST_ALERT_STATE_MALFORMED="false"
    export MST_ALERT_STATE_TARGET_KIND=""
    export MST_ALERT_STATE_PERSISTENCE_AVAILABLE="false"
    export MST_ALERT_STATE_ERROR_KIND=""

    target_kind="$(mst_alert_state_target_kind "${state_file}")" || target_kind="special"
    export MST_ALERT_STATE_TARGET_KIND="${target_kind}"

    case "${target_kind}" in
        missing|regular)
            mst_fs_validate_runtime_file_path "${state_file}" >/dev/null || {
                export MST_ALERT_STATE_ERROR_KIND="invalid_state_target"
                return 0
            }
            export MST_ALERT_STATE_PERSISTENCE_AVAILABLE="true"
            ;;
        *)
            export MST_ALERT_STATE_ERROR_KIND="invalid_state_target"
            ;;
    esac
}

# Load alert state rows safely.
mst_alert_load_state() {
    local state_file="${1:?state file required}"
    local line field_count row_status row_delivered row_active row_confirmed
    declare -ga MST_ALERT_STATE_ROWS=()
    export MST_ALERT_STATE_MALFORMED="false"

    [[ "${MST_ALERT_STATE_PERSISTENCE_AVAILABLE:-false}" == "true" ]] || return 0
    [[ -e "${state_file}" ]] || return 0
    while IFS= read -r line || [[ -n "${line}" ]]; do
        [[ -n "${line}" ]] || continue
        field_count="$(awk -F'|' '{ print NF }' <<< "${line}")"
        if [[ "${field_count}" -eq 9 ]]; then
            IFS='|' read -r _event _module _record row_status _first _last _occ row_delivered row_active <<< "${line}"
            row_confirmed="false"
            case "${row_status}" in
                warn|critical|unavailable|unknown)
                    if [[ "${row_active}" == "true" ]] && [[ "${row_delivered:-0}" =~ ^[0-9]+$ ]] && (( 10#${row_delivered} > 0 )); then
                        row_confirmed="true"
                    fi
                    ;;
            esac
            line="${line}|${row_confirmed}"
        elif [[ "${field_count}" -ne 10 ]]; then
            export MST_ALERT_STATE_MALFORMED="true"
            continue
        fi
        MST_ALERT_STATE_ROWS+=("${line}")
    done < "${state_file}"
}

# Find prior state row for one event id.
mst_alert_state_row_for_event() {
    local event_id="${1:?event required}"
    local row row_event
    for row in "${MST_ALERT_STATE_ROWS[@]:-}"; do
        IFS='|' read -r row_event _module _record _status _first _last _occ _delivered _active _confirmed <<< "${row}"
        [[ "${row_event}" == "${event_id}" ]] && {
            printf '%s' "${row}"
            return 0
        }
    done
    return 1
}

# Upsert one state row in memory.
mst_alert_state_upsert() {
    local new_row="${1:?row required}"
    local event_id="${new_row%%|*}"
    local row row_event updated=0 new_rows=()

    for row in "${MST_ALERT_STATE_ROWS[@]:-}"; do
        IFS='|' read -r row_event _module _record _status _first _last _occ _delivered _active _confirmed <<< "${row}"
        if [[ "${row_event}" == "${event_id}" ]]; then
            new_rows+=("${new_row}")
            updated=1
        else
            new_rows+=("${row}")
        fi
    done
    (( updated == 1 )) || new_rows+=("${new_row}")
    MST_ALERT_STATE_ROWS=("${new_rows[@]}")
}

# Persist alert state atomically.
mst_alert_save_state() {
    local state_file="${1:?state file required}"
    local content

    mst_alert_prepare_state_target "${state_file}"
    [[ "${MST_ALERT_STATE_PERSISTENCE_AVAILABLE:-false}" == "true" ]] || {
        export MST_ALERT_STATE_SAVE_ERROR="invalid_state_target"
        return 2
    }
    content="$(printf '%s\n' "${MST_ALERT_STATE_ROWS[@]:-}")"
    mst_fs_atomic_write "${state_file}" 0660 "${content}" || {
        export MST_ALERT_STATE_SAVE_ERROR="write_failed"
        return 1
    }
    export MST_ALERT_STATE_SAVE_ERROR=""
}

# Append one alert event row for rendering.
mst_alert_add_event() {
    local event_id="${1:?event required}"
    local module_name="${2:?module required}"
    local record_key="${3:?record required}"
    local current_status="${4:-unknown}"
    local previous_status="${5:-}"
    local transition_type="${6:?transition required}"
    local first_seen="${7:-}"
    local last_seen="${8:-}"
    local occurrence_count="${9:-0}"
    local alert_reason="${10:-}"
    local summary="${11:-}"
    local should_deliver="${12:-false}"
    local suppressed="${13:-false}"
    local suppression_reason="${14:-}"
    local recovery="${15:-false}"
    local timestamp

    timestamp="$(mst_alert_now_utc)"
    MST_ALERT_EVENTS+=("$(mst_mrrf_sanitize_text "${event_id}" 96)${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${module_name}" 32)${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${record_key}" 96)${MST_MRRF_FIELD_SEPARATOR}$(mst_alert_normalize_status "${current_status}")${MST_MRRF_FIELD_SEPARATOR}$(mst_alert_normalize_status "${previous_status}")${MST_MRRF_FIELD_SEPARATOR}${transition_type}${MST_MRRF_FIELD_SEPARATOR}${first_seen}${MST_MRRF_FIELD_SEPARATOR}${last_seen}${MST_MRRF_FIELD_SEPARATOR}${occurrence_count}${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${alert_reason}" 96)${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${summary}" 160)${MST_MRRF_FIELD_SEPARATOR}${should_deliver}${MST_MRRF_FIELD_SEPARATOR}${suppressed}${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${suppression_reason}" 96)${MST_MRRF_FIELD_SEPARATOR}${recovery}${MST_MRRF_FIELD_SEPARATOR}${timestamp}")
}

# Return success if a status is alert-active.
mst_alert_status_is_active() {
    case "${1:-unknown}" in
        warn|critical|unavailable|unknown) return 0 ;;
        *) return 1 ;;
    esac
}

# Return the configured number of consecutive occurrences required before first delivery.
mst_alert_min_occurrences_before_delivery() {
    local configured="${MST_ALERT_MIN_OCCURRENCES_BEFORE_DELIVERY:-2}"
    [[ "${configured}" =~ ^[0-9]+$ ]] && (( 10#${configured} > 0 )) || configured="2"
    printf '%s' "${configured}"
}

# Return success if persisted state has any confirmed active alert issue.
mst_alert_has_confirmed_active_issue() {
    local state_file row _event _module _record status _first _last _occ _delivered active_flag confirmed

    declare -ga MST_ALERT_STATE_ROWS=()
    state_file="$(mst_alert_state_file_path)" || return 1
    mst_alert_prepare_state_target "${state_file}"
    [[ "${MST_ALERT_STATE_PERSISTENCE_AVAILABLE:-false}" == "true" ]] || return 1
    mst_alert_load_state "${state_file}"

    for row in "${MST_ALERT_STATE_ROWS[@]:-}"; do
        IFS='|' read -r _event _module _record status _first _last _occ _delivered active_flag confirmed <<< "${row}"
        [[ "${active_flag}" == "true" ]] || continue
        [[ "${confirmed}" == "true" ]] || continue
        mst_alert_status_is_active "${status}" && return 0
    done
    return 1
}

# Evaluate one record against policy and prior state.
mst_alert_evaluate_record() {
    local module_name="${1:?module required}"
    local record_object="${2:?record required}"
    local result_id check_name target_name record_module status summary record_key event_id
    local previous_row previous_status="" first_seen="" previous_last_seen="" occurrence_count=0 last_delivered=0 active_flag="false" confirmed="false"
    local now_epoch now_utc transition should_deliver="false" suppressed="false" suppression_reason="" recovery="false" alert_reason=""
    local new_last_delivered state_active min_occurrences

    record_module="$(mst_alert_json_string_field "${record_object}" "module")"
    result_id="$(mst_alert_json_string_field "${record_object}" "result_id")"
    check_name="$(mst_alert_json_string_field "${record_object}" "check")"
    target_name="$(mst_alert_json_string_field "${record_object}" "target")"
    status="$(mst_alert_normalize_status "$(mst_alert_json_string_field "${record_object}" "status")")"
    summary="$(mst_alert_json_string_field "${record_object}" "summary")"
    [[ "${record_module}" == "${module_name}" ]] || {
        mst_alert_add_event "invalid.${module_name}.$(mst_alert_sanitize_id "${result_id:-record}")" "${module_name}" "${result_id:-record}" "unknown" "" "SUPPRESSED" "" "" "0" "malformed_record" "Malformed MRRF1 record in ${module_name}" "false" "true" "malformed_record" "false"
        return 0
    }
    [[ -n "${result_id}" ]] || {
        mst_alert_add_event "invalid.${module_name}.record" "${module_name}" "record" "unknown" "" "SUPPRESSED" "" "" "0" "malformed_record" "MRRF1 record is missing result_id" "false" "true" "malformed_record" "false"
        return 0
    }

    record_key="${result_id}.${check_name:-check}.${target_name:-target}"
    event_id="$(mst_alert_event_id "${module_name}" "${record_key}")"
    now_epoch="$(mst_alert_now_epoch)"
    now_utc="$(mst_alert_now_utc)"
    min_occurrences="$(mst_alert_min_occurrences_before_delivery)"
    previous_row="$(mst_alert_state_row_for_event "${event_id}" || true)"
    if [[ -n "${previous_row}" ]]; then
        IFS='|' read -r _event _module _record previous_status first_seen previous_last_seen occurrence_count last_delivered active_flag confirmed <<< "${previous_row}"
    fi
    new_last_delivered="${last_delivered:-0}"
    state_active="false"

    if [[ "$(mst_alert_bool "${MST_ALERTS_ENABLED:-false}")" != "true" ]]; then
        [[ -n "${first_seen}" ]] || first_seen="${now_utc}"
        occurrence_count=$(( occurrence_count + 1 ))
        confirmed="false"
        transition="SUPPRESSED"
        suppressed="true"
        suppression_reason="alerts_disabled"
        alert_reason="alerts_disabled"
    elif ! mst_alert_status_is_active "${status}"; then
        [[ -n "${first_seen}" ]] || first_seen="${now_utc}"
        occurrence_count=0
        confirmed="false"
        if [[ "${active_flag}" == "true" ]] && mst_alert_status_is_active "${previous_status}"; then
            transition="RECOVERED"
            recovery="true"
            alert_reason="recovered"
            if [[ "$(mst_alert_bool "${MST_ALERT_RECOVERY_ENABLED:-true}")" == "true" ]]; then
                should_deliver="true"
                new_last_delivered="${now_epoch}"
            else
                suppressed="true"
                suppression_reason="recovery_disabled"
            fi
        else
            transition="UNCHANGED"
            suppressed="true"
            suppression_reason="healthy"
            alert_reason="healthy"
        fi
    elif ! mst_alert_policy_enabled_for_status "${status}"; then
        if [[ "${active_flag}" == "true" ]] && mst_alert_status_is_active "${previous_status}"; then
            occurrence_count=$(( occurrence_count + 1 ))
        else
            first_seen="${now_utc}"
            occurrence_count=1
        fi
        confirmed="false"
        transition="SUPPRESSED"
        suppressed="true"
        suppression_reason="policy_disabled"
        alert_reason="policy_disabled"
        state_active="true"
    elif [[ "${active_flag}" != "true" ]] || [[ -z "${previous_status}" ]]; then
        first_seen="${now_utc}"
        occurrence_count=1
        confirmed="false"
        transition="NEW"
        if (( occurrence_count >= min_occurrences )); then
            should_deliver="true"
            confirmed="true"
            new_last_delivered="${now_epoch}"
        else
            suppressed="true"
            suppression_reason="confirmation_pending"
        fi
        alert_reason="new_$(mst_alert_status_label "${status}")"
        state_active="true"
    elif [[ "${status}" != "${previous_status}" ]]; then
        occurrence_count=$(( occurrence_count + 1 ))
        transition="CHANGED"
        if [[ "${confirmed}" == "true" ]] || (( occurrence_count >= min_occurrences )); then
            should_deliver="true"
            confirmed="true"
            new_last_delivered="${now_epoch}"
        else
            suppressed="true"
            suppression_reason="confirmation_pending"
        fi
        alert_reason="status_changed"
        state_active="true"
    elif [[ "${confirmed}" != "true" ]]; then
        occurrence_count=$(( occurrence_count + 1 ))
        transition="UNCHANGED"
        if (( occurrence_count >= min_occurrences )); then
            should_deliver="true"
            confirmed="true"
            new_last_delivered="${now_epoch}"
            alert_reason="confirmation_threshold_met"
        else
            suppressed="true"
            suppression_reason="confirmation_pending"
            alert_reason="duplicate_active_event"
        fi
        state_active="true"
    elif [[ "$(mst_alert_bool "${MST_ALERT_REPEAT_ENABLED:-false}")" == "true" ]] && (( now_epoch - last_delivered >= MST_ALERT_REPEAT_INTERVAL_SECONDS )); then
        occurrence_count=$(( occurrence_count + 1 ))
        transition="REPEATED"
        should_deliver="true"
        new_last_delivered="${now_epoch}"
        alert_reason="repeat_interval_elapsed"
        state_active="true"
    else
        occurrence_count=$(( occurrence_count + 1 ))
        transition="UNCHANGED"
        suppressed="true"
        if (( now_epoch - last_delivered < MST_ALERT_COOLDOWN_SECONDS )); then
            suppression_reason="cooldown"
        else
            suppression_reason="repeat_disabled"
        fi
        alert_reason="duplicate_active_event"
        state_active="true"
    fi

    mst_alert_add_event "${event_id}" "${module_name}" "${record_key}" "${status}" "${previous_status}" "${transition}" "${first_seen}" "${now_utc}" "${occurrence_count}" "${alert_reason}" "${summary:-Alert status evaluated.}" "${should_deliver}" "${suppressed}" "${suppression_reason}" "${recovery}"
    mst_alert_state_upsert "${event_id}|${module_name}|${record_key}|${status}|${first_seen}|${now_utc}|${occurrence_count}|${new_last_delivered}|${state_active}|${confirmed}"
}

# Evaluate all configured MRRF1 inputs.
mst_alert_evaluate() {
    local update_state="${1:?update state required}"
    shift || true
    local state_file key env_name raw_json compact_json records_payload record_object saw_input=0
    local deliverable=0 suppressed=0 recovery=0 invalid=0 total=0 row should_deliver row_suppressed row_recovery transition

    declare -ga MST_ALERT_EVENTS=()
    declare -ga MST_ALERT_STATE_ROWS=()

    state_file="$(mst_alert_state_file_path)" || {
        mst_alert_add_event "invalid.state" "alert" "state" "unknown" "" "SUPPRESSED" "" "" "0" "state_unavailable" "Alert state path is not approved or writable." "false" "true" "state_unavailable" "false"
        export MST_ALERT_EXIT_CODE="${MST_EXIT_SECURITY}"
        return 0
    }
    mst_alert_prepare_state_target "${state_file}"
    if [[ "${MST_ALERT_STATE_ERROR_KIND:-}" == "invalid_state_target" ]]; then
        mst_alert_add_event "invalid.state_target" "alert" "state" "unknown" "" "SUPPRESSED" "" "" "0" "invalid_state_target" "Alert state target is not a valid regular file; persistence disabled." "false" "true" "invalid_state_target" "false"
    fi
    mst_alert_load_state "${state_file}"
    if [[ "${MST_ALERT_STATE_MALFORMED:-false}" == "true" ]]; then
        mst_alert_add_event "invalid.state" "alert" "state" "unknown" "" "SUPPRESSED" "" "" "0" "malformed_state" "Malformed alert state was ignored safely." "false" "true" "malformed_state" "false"
    fi

    mst_alert_load_argument_reports "$@"
    mst_alert_load_persisted_reports

    while IFS='|' read -r key env_name; do
        mst_alert_module_enabled "${key}" || continue
        raw_json="$(mst_alert_json_for_env "${env_name}")"
        [[ -n "${raw_json}" ]] || continue
        saw_input=1
        compact_json="$(mst_alert_compact_json "${raw_json}")"
        if ! mst_alert_validate_mrrf_report "${key}" "${compact_json}"; then
            mst_alert_add_event "invalid.${key}" "${key}" "module_report" "unknown" "" "SUPPRESSED" "" "" "0" "missing_or_malformed_input" "No valid MRRF1 aggregate report was supplied for ${key}." "false" "true" "invalid_input" "false"
            continue
        fi
        records_payload="$(mst_alert_records_payload "${compact_json}")"
        while IFS= read -r record_object || [[ -n "${record_object}" ]]; do
            [[ -n "${record_object}" ]] || continue
            mst_alert_evaluate_record "${key}" "${record_object}"
        done < <(mst_alert_each_record_object "${records_payload}")
    done < <(mst_alert_module_catalog)

    if (( saw_input == 0 )); then
        mst_alert_add_event "invalid.no_input" "alert" "input" "unknown" "" "SUPPRESSED" "" "" "0" "no_input_reports" "No MRRF1 aggregate reports were supplied." "false" "true" "no_input_reports" "false"
    fi

    if [[ "${update_state}" == "true" ]]; then
        if [[ "${MST_ALERT_STATE_PERSISTENCE_AVAILABLE:-false}" != "true" ]]; then
            mst_alert_add_event "invalid.state_persistence" "alert" "state" "unknown" "" "SUPPRESSED" "" "" "0" "state_persistence_unavailable" "Alert state persistence is unavailable; current evaluation was not saved." "false" "true" "state_persistence_unavailable" "false"
        else
            mst_alert_save_state "${state_file}" || {
                if [[ "${MST_ALERT_STATE_SAVE_ERROR:-}" == "invalid_state_target" ]]; then
                    mst_alert_add_event "invalid.state_persistence" "alert" "state" "unknown" "" "SUPPRESSED" "" "" "0" "state_persistence_unavailable" "Alert state persistence became unavailable; current evaluation was not saved." "false" "true" "state_persistence_unavailable" "false"
                else
                    mst_alert_add_event "invalid.state_write" "alert" "state" "unknown" "" "SUPPRESSED" "" "" "0" "state_write_failed" "Alert state could not be written safely." "false" "true" "state_write_failed" "false"
                fi
            }
        fi
    fi

    for row in "${MST_ALERT_EVENTS[@]:-}"; do
        IFS="${MST_MRRF_FIELD_SEPARATOR}" read -r _event _module _record _current _previous transition _first _last _occ _reason _summary should_deliver row_suppressed _suppression row_recovery _timestamp <<< "${row}"
        total=$(( total + 1 ))
        [[ "${should_deliver}" == "true" ]] && deliverable=$(( deliverable + 1 ))
        [[ "${row_suppressed}" == "true" ]] && suppressed=$(( suppressed + 1 ))
        [[ "${row_recovery}" == "true" ]] && recovery=$(( recovery + 1 ))
        [[ "${transition}" == "SUPPRESSED" ]] && invalid=$(( invalid + 1 ))
    done

    export MST_ALERT_STATE_FILE="${state_file}"
    export MST_ALERT_TOTAL_EVENTS="${total}"
    export MST_ALERT_DELIVERABLE_EVENTS="${deliverable}"
    export MST_ALERT_SUPPRESSED_EVENTS="${suppressed}"
    export MST_ALERT_RECOVERY_EVENTS="${recovery}"
    export MST_ALERT_INVALID_EVENTS="${invalid}"
    if (( deliverable > 0 || invalid > 0 )); then
        export MST_ALERT_EXIT_CODE="${MST_EXIT_PARTIAL}"
    else
        export MST_ALERT_EXIT_CODE="${MST_EXIT_OK}"
    fi
}
