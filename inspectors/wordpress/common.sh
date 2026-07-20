#!/usr/bin/env bash
# Shared helpers for the WordPress module.

# Reuse website read-only HTTP helpers where appropriate.
# shellcheck source=inspectors/website/common.sh
source "${MST_INSPECTOR_DIR}/website/common.sh"

# Apply default configuration for WordPress collectors.
mst_wordpress_init_defaults() {
    export MST_WORDPRESS_TARGETS="${MST_WORDPRESS_TARGETS:-}"
    export MST_WORDPRESS_AUTO_DISCOVER="${MST_WORDPRESS_AUTO_DISCOVER:-no}"
    export MST_WORDPRESS_CRON_OVERDUE_WARN_COUNT="${MST_WORDPRESS_CRON_OVERDUE_WARN_COUNT:-0}"
    export MST_WORDPRESS_TIMEOUT_SECONDS="${MST_WORDPRESS_TIMEOUT_SECONDS:-${MST_TIMEOUT_SECONDS:-${MST_DEFAULT_TIMEOUT_SECONDS}}}"
}

# Normalize one boolean-like flag to true or false.
mst_wordpress_normalize_boolean() {
    case "${1:-}" in
        1|yes|true) printf 'true' ;;
        *) printf 'false' ;;
    esac
}

# Trim leading and trailing whitespace from a string.
mst_wordpress_trim() {
    local value="${1-}"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "${value}"
}

# Return the configured WordPress target catalog in normalized form.
mst_wordpress_targets_catalog() {
    local spec="${MST_WORDPRESS_TARGETS:-}"
    local entry trimmed name url document_root wp_config_path wp_cli_path enabled
    local discovered_name discovered_root discovered_url
    local old_ifs="${IFS}"
    local -A configured_names=()
    local -A configured_urls=()

    IFS=';'
    for entry in ${spec}; do
        trimmed="${entry#"${entry%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -n "${trimmed}" ]] || continue
        IFS='|' read -r name url document_root wp_config_path wp_cli_path enabled <<< "${trimmed}"
        [[ -n "${wp_cli_path:-}" ]] || wp_cli_path="wp"
        [[ -n "${enabled:-}" ]] || enabled="true"
        configured_names["${name}"]=1
        configured_urls["${url}"]=1
        printf '%s|%s|%s|%s|%s|%s\n' \
            "${name}" \
            "${url}" \
            "${document_root:-}" \
            "${wp_config_path:-}" \
            "${wp_cli_path}" \
            "$(mst_wordpress_normalize_boolean "${enabled}")"
    done
    IFS="${old_ifs}"

    [[ "$(mst_wordpress_normalize_boolean "${MST_WORDPRESS_AUTO_DISCOVER:-no}")" == "true" ]] || return 0
    while IFS='|' read -r discovered_name discovered_root || [[ -n "${discovered_name:-}${discovered_root:-}" ]]; do
        [[ -n "${discovered_name:-}" ]] || continue
        mst_discover_site_is_wordpress "${discovered_root}" || continue
        discovered_url="https://${discovered_name}"
        [[ -z "${configured_names[${discovered_name}]:-}" ]] || continue
        [[ -z "${configured_urls[${discovered_url}]:-}" ]] || continue
        configured_names["${discovered_name}"]=1
        configured_urls["${discovered_url}"]=1
        printf '%s|%s|%s||wp|true\n' \
            "${discovered_name}" \
            "${discovered_url}" \
            "${discovered_root}"
    done < <(mst_discover_web_sites)
}

# Create a stable result identifier fragment from a site name.
mst_wordpress_result_suffix() {
    local name="${1:?name required}"
    local lowered
    lowered="$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]')"
    lowered="$(printf '%s' "${lowered}" | tr -cs 'a-z0-9' '_')"
    lowered="${lowered##_}"
    lowered="${lowered%%_}"
    printf '%s' "${lowered:-site}"
}

# Resolve a wp-config path from explicit config or document root.
mst_wordpress_resolve_wp_config_path() {
    local explicit_path="${1:-}"
    local document_root="${2:-}"

    if [[ -n "${explicit_path}" ]]; then
        printf '%s' "${explicit_path}"
    elif [[ -n "${document_root}" ]]; then
        printf '%s' "${document_root}/wp-config.php"
    else
        printf ''
    fi
}

# Return success if the configured WP-CLI executable is available.
mst_wordpress_wp_cli_exists() {
    local wp_cli_path="${1:?wp cli path required}"
    if [[ "${wp_cli_path}" == */* ]]; then
        [[ -x "${wp_cli_path}" ]]
    else
        mst_command_exists "${wp_cli_path}"
    fi
}

# Run one read-only WP-CLI command and capture stdout.
mst_wordpress_wp_cli_capture() {
    local wp_cli_path="${1:?wp cli path required}"
    local document_root="${2:-}"
    local site_url="${3:?site url required}"
    local timeout_seconds="${4:?timeout required}"
    shift 4 || true
    local -a cmd=( "${wp_cli_path}" )

    if [[ -n "${document_root}" ]]; then
        cmd+=( "--path=${document_root}" )
    fi
    cmd+=( "--url=${site_url}" "$@" )
    mst_exec_capture_stdout "${timeout_seconds}" "${cmd[@]}"
}

# Return the exit status of one read-only WP-CLI command.
mst_wordpress_wp_cli_run() {
    local wp_cli_path="${1:?wp cli path required}"
    local document_root="${2:-}"
    local site_url="${3:?site url required}"
    local timeout_seconds="${4:?timeout required}"
    shift 4 || true
    local -a cmd=( "${wp_cli_path}" )

    if [[ -n "${document_root}" ]]; then
        cmd+=( "--path=${document_root}" )
    fi
    cmd+=( "--url=${site_url}" "$@" )
    timeout "${timeout_seconds}" "${cmd[@]}" >/dev/null 2>&1
}

# Parse one WordPress constant from wp-config.php.
mst_wordpress_read_config_constant() {
    local config_path="${1:?config path required}"
    local constant_name="${2:?constant required}"
    local line trimmed regex

    [[ -r "${config_path}" ]] || return 1
    regex="define[[:space:]]*\\([[:space:]]*['\"]${constant_name}['\"][[:space:]]*,[[:space:]]*([^)]*)\\)"
    while IFS= read -r line || [[ -n "${line}" ]]; do
        trimmed="${line%$'\r'}"
        if [[ "${trimmed}" =~ ${regex} ]]; then
            printf '%s' "$(mst_wordpress_normalize_php_value "${BASH_REMATCH[1]}")"
            return 0
        fi
    done < "${config_path}"
    return 1
}

# Normalize a PHP literal-like value to a simple textual form.
mst_wordpress_normalize_php_value() {
    local raw_value
    raw_value="$(mst_wordpress_trim "${1:-}")"
    raw_value="${raw_value%\"}"
    raw_value="${raw_value#\"}"
    raw_value="${raw_value%\'}"
    raw_value="${raw_value#\'}"
    raw_value="${raw_value%%//*}"
    raw_value="$(mst_wordpress_trim "${raw_value}")"
    case "${raw_value,,}" in
        true|1) printf 'true' ;;
        false|0) printf 'false' ;;
        *) printf '%s' "${raw_value}" ;;
    esac
}

# Parse a WP-CLI count response to an integer or zero.
mst_wordpress_parse_count() {
    local value="${1:-0}"
    value="${value%$'\r'}"
    value="${value%%[[:space:]]*}"
    if [[ "${value}" =~ ^[0-9]+$ ]]; then
        printf '%s' "${value}"
    else
        printf '0'
    fi
}

# Parse plugin list CSV and return total|active|inactive|updates.
mst_wordpress_plugin_counts() {
    local csv_payload="${1:-}"
    local line _name status update total=0 active=0 inactive=0 updates=0
    local first_line=1

    while IFS=',' read -r _name status update || [[ -n "${_name:-}" ]]; do
        _name="${_name%$'\r'}"
        status="${status%$'\r'}"
        update="${update%$'\r'}"
        if (( first_line == 1 )); then
            first_line=0
            [[ "${_name}" == "name" ]] && continue
        fi
        [[ -n "${_name}" ]] || continue
        total=$(( total + 1 ))
        case "${status}" in
            active|active-network) active=$(( active + 1 )) ;;
            inactive) inactive=$(( inactive + 1 )) ;;
        esac
        if [[ "${update}" == "available" ]]; then
            updates=$(( updates + 1 ))
        fi
    done <<< "${csv_payload}"

    printf '%s|%s|%s|%s' "${total}" "${active}" "${inactive}" "${updates}"
}

# Parse theme list CSV and return active_theme|updates.
mst_wordpress_theme_info() {
    local csv_payload="${1:-}"
    local line name status update active_theme="" updates=0
    local first_line=1

    while IFS=',' read -r name status update || [[ -n "${name:-}" ]]; do
        name="${name%$'\r'}"
        status="${status%$'\r'}"
        update="${update%$'\r'}"
        if (( first_line == 1 )); then
            first_line=0
            [[ "${name}" == "name" ]] && continue
        fi
        [[ -n "${name}" ]] || continue
        if [[ "${status}" == "active" ]]; then
            active_theme="${name}"
        fi
        if [[ "${update}" == "available" ]]; then
            updates=$(( updates + 1 ))
        fi
    done <<< "${csv_payload}"

    printf '%s|%s' "${active_theme}" "${updates}"
}

# Return the REST API endpoint for one site URL.
mst_wordpress_rest_url() {
    local site_url="${1:?site url required}"
    site_url="${site_url%/}"
    printf '%s/wp-json/' "${site_url}"
}

# Probe a WordPress site URL and return reachability plus status code.
mst_wordpress_site_probe() {
    local site_url="${1:?site url required}"
    local timeout_seconds="${2:?timeout required}"
    mst_website_curl_probe "${site_url}" "${timeout_seconds}" "true"
}

# Probe the REST API endpoint and return reachability plus status code.
mst_wordpress_rest_probe() {
    local site_url="${1:?site url required}"
    local timeout_seconds="${2:?timeout required}"
    mst_website_curl_probe "$(mst_wordpress_rest_url "${site_url}")" "${timeout_seconds}" "true"
}

# Detect hostname for aggregate documents.
mst_wordpress_detect_hostname() {
    mst_website_detect_hostname
}

# Initialize one WordPress MRRF1 record.
mst_wordpress_record_init() {
    local record_name="${1:?record required}"
    local result_id="${2:?result id required}"
    local target_name="${3:?target required}"
    local provenance="${4:?provenance required}"
    local -n record_ref="${record_name}"

    record_ref[result_id]="${result_id}"
    record_ref[module]="wordpress"
    record_ref[check]="site_health"
    record_ref[target]="${target_name}"
    record_ref[status]="unknown"
    record_ref[severity]="unknown"
    record_ref[score]="null"
    record_ref[summary]="WordPress observation unavailable."
    record_ref[source_list]="wp-cli,rest,config,website"
    record_ref[provenance]="${provenance}"
    record_ref[privilege_requirement]="none"
    record_ref[redactions_present]="false"
}

# Finalize one WordPress record.
mst_wordpress_record_finalize() {
    local record_name="${1:?record required}"
    local started_ms="${2:?started required}"
    local finished_ms duration_ms
    local -n record_ref="${record_name}"

    finished_ms="$(mst_mrrf_now_epoch_ms)"
    duration_ms=$(( finished_ms - started_ms ))
    record_ref[duration_ms]="${duration_ms}"
    record_ref[observed_at]="$(mst_mrrf_now_utc)"
}

# Append one MRRF1 detail.
mst_wordpress_add_detail() {
    local details_name="${1:?details required}"
    local key_name="${2:?key required}"
    local label="${3:?label required}"
    local value_type="${4:?type required}"
    local value="${5:-}"
    local unit="${6:-}"
    local redacted="${7:-false}"
    local -n details_ref="${details_name}"

    details_ref+=("$(mst_mrrf_pack_detail "${key_name}" "${label}" "${value_type}" "${value}" "${unit}" "${redacted}")")
}

# Append one renderer row.
mst_wordpress_add_row() {
    local rows_name="${1:?rows required}"
    local label="${2:?label required}"
    local value="${3:-}"
    local -n rows_ref="${rows_name}"

    rows_ref+=("$(mst_mrrf_sanitize_text "${label}" 64)${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${value}" 200)")
}

# Append one MRRF1 error.
mst_wordpress_add_error() {
    local errors_name="${1:?errors required}"
    local category="${2:?category required}"
    local code="${3:?code required}"
    local message="${4:?message required}"
    local -n errors_ref="${errors_name}"

    errors_ref+=("$(mst_mrrf_pack_error "${category}" "${code}" "${message}")")
}

# Mark a WordPress record with a failure state.
mst_wordpress_mark_failure() {
    local record_name="${1:?record required}"
    local errors_name="${2:?errors required}"
    local status="${3:?status required}"
    local severity="${4:?severity required}"
    local summary="${5:?summary required}"
    local error_category="${6:?category required}"
    local error_code="${7:?code required}"
    local error_message="${8:?message required}"
    local -n record_ref="${record_name}"

    record_ref[status]="${status}"
    record_ref[severity]="${severity}"
    record_ref[summary]="${summary}"
    mst_wordpress_add_error "${errors_name}" "${error_category}" "${error_code}" "${error_message}"
}

# Build a generic internal failure record for collector isolation.
mst_wordpress_build_internal_failure_record() {
    local site_index="${1:?index required}"
    local name="${2:?name required}"
    local record_name="${3:?record required}"
    local details_name="${4:?details required}"
    local errors_name="${5:?errors required}"
    local message="${6:?message required}"
    local started_ms
    local -n details_ref="${details_name}"
    local -n errors_ref="${errors_name}"

    started_ms="$(mst_mrrf_now_epoch_ms)"
    details_ref=()
    errors_ref=()
    mst_wordpress_record_init "${record_name}" "res_wordpress.${site_index}.$(mst_wordpress_result_suffix "${name}")" "${name}" "Collector fallback path."
    mst_wordpress_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "${message}" "internal" "COLLECTOR_FAILURE" "${message}"
    mst_wordpress_record_finalize "${record_name}" "${started_ms}"
}

# Return the worst MRRF1 status from a status array.
mst_wordpress_worst_status() {
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

# Return the worst MRRF1 severity from a severity array.
mst_wordpress_worst_severity() {
    local array_name="${1:?array required}"
    local -n values_ref="${array_name}"
    local value rank worst_value="ok" worst_rank=0

    for value in "${values_ref[@]}"; do
        case "${value}" in
            critical) rank=3 ;;
            unknown) rank=2 ;;
            warning) rank=1 ;;
            ok) rank=0 ;;
            *) rank=2 ;;
        esac
        if (( rank > worst_rank )); then
            worst_rank="${rank}"
            worst_value="${value}"
        fi
    done
    printf '%s' "${worst_value}"
}

# Return the WordPress command exit code from record statuses.
mst_wordpress_report_exit_code() {
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

# Build one module summary JSON object.
mst_wordpress_module_summary_json() {
    local module_name="${1:?module required}"
    local record_count="${2:?record count required}"
    local status="${3:?status required}"
    local severity="${4:?severity required}"

    printf '{"module":"%s","record_count":%s,"status":"%s","severity":"%s","score":null}' \
        "$(mst_mrrf_json_escape "${module_name}")" \
        "${record_count}" \
        "$(mst_mrrf_json_escape "${status}")" \
        "$(mst_mrrf_json_escape "${severity}")"
}

# Collect one configured WordPress site.
mst_wordpress_collect_site() {
    local site_index="${1:?index required}"
    local name="${2:?name required}"
    local site_url="${3:?site url required}"
    local document_root="${4:-}"
    local wp_config_path="${5:-}"
    local wp_cli_path="${6:?wp cli path required}"
    local enabled="${7:?enabled required}"
    local record_name="${8:?record required}"
    local details_name="${9:?details required}"
    local errors_name="${10:?errors required}"
    local rows_name="${11:?rows required}"
    local started_ms effective_config_path wp_cli_available website_probe website_exit website_status
    local rest_probe rest_exit rest_status site_reachable rest_reachable
    local core_installed core_version core_updates db_ok maintenance_status
    local plugin_csv plugin_counts total_plugins active_plugins inactive_plugins plugin_updates
    local theme_csv theme_info active_theme theme_updates
    local debug_mode cron_enabled overdue_events status severity summary
    local -n record_ref="${record_name}"

    mst_wordpress_init_defaults
    started_ms="$(mst_mrrf_now_epoch_ms)"
    effective_config_path="$(mst_wordpress_resolve_wp_config_path "${wp_config_path}" "${document_root}")"
    mst_wordpress_record_init "${record_name}" "res_wordpress.${site_index}.$(mst_wordpress_result_suffix "${name}")" "${name}" "Derived from read-only WP-CLI commands, REST API probing, wp-config.php inspection, and website helpers."

    if [[ "${enabled}" != "true" ]]; then
        mst_wordpress_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "${name} is disabled in configuration." "configuration" "WORDPRESS_DISABLED" "WordPress site ${name} is disabled in configuration."
        mst_wordpress_add_detail "${details_name}" "site_name" "Site Name" "string" "${name}" "" "false"
        mst_wordpress_add_detail "${details_name}" "site_url" "Site URL" "string" "${site_url}" "" "false"
        mst_wordpress_add_row "${rows_name}" "Name" "${name}"
        mst_wordpress_add_row "${rows_name}" "URL" "${site_url}"
        mst_wordpress_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    status="ok"
    severity="ok"
    site_reachable="false"
    rest_reachable="false"
    core_installed="false"
    core_version=""
    core_updates="0"
    db_ok="false"
    maintenance_status="unknown"
    total_plugins="0"
    active_plugins="0"
    inactive_plugins="0"
    plugin_updates="0"
    active_theme=""
    theme_updates="0"
    debug_mode="unknown"
    cron_enabled="true"
    overdue_events="0"

    if mst_command_exists curl; then
        website_exit=0
        website_probe="$(mst_wordpress_site_probe "${site_url}" "${MST_WORDPRESS_TIMEOUT_SECONDS}" 2>&1)" || website_exit=$?
        if [[ "${website_exit}" -eq 0 ]]; then
            website_status="$(mst_website_payload_value "${website_probe}" "response_code" || printf '0')"
            if [[ "${website_status}" =~ ^[23][0-9][0-9]$ ]]; then
                site_reachable="true"
            fi
        fi

        rest_exit=0
        rest_probe="$(mst_wordpress_rest_probe "${site_url}" "${MST_WORDPRESS_TIMEOUT_SECONDS}" 2>&1)" || rest_exit=$?
        if [[ "${rest_exit}" -eq 0 ]]; then
            rest_status="$(mst_website_payload_value "${rest_probe}" "response_code" || printf '0')"
            if [[ "${rest_status}" =~ ^[23][0-9][0-9]$ ]]; then
                rest_reachable="true"
            fi
        else
            rest_status="0"
        fi
    else
        website_status="0"
        rest_status="0"
    fi

    if [[ "${site_reachable}" != "true" ]]; then
        status="critical"
        severity="critical"
        mst_wordpress_add_error "${errors_name}" "network" "WORDPRESS_NOT_REACHABLE" "WordPress site ${site_url} is not reachable."
    fi

    if [[ "${rest_reachable}" != "true" ]]; then
        if [[ "${status}" == "ok" ]]; then
            status="warn"
            severity="warning"
        fi
        mst_wordpress_add_error "${errors_name}" "network" "REST_API_UNAVAILABLE" "WordPress REST API is not reachable for ${site_url}."
    fi

    if [[ -n "${effective_config_path}" ]]; then
        debug_mode="$(mst_wordpress_read_config_constant "${effective_config_path}" "WP_DEBUG" || printf 'unknown')"
        if [[ "$(mst_wordpress_read_config_constant "${effective_config_path}" "DISABLE_WP_CRON" || printf 'false')" == "true" ]]; then
            cron_enabled="false"
        fi
    fi

    if [[ "${debug_mode}" == "true" ]] && [[ "${status}" == "ok" ]]; then
        status="warn"
        severity="warning"
    fi

    wp_cli_available="false"
    if mst_wordpress_wp_cli_exists "${wp_cli_path}"; then
        wp_cli_available="true"
    else
        status="unavailable"
        severity="unknown"
        mst_wordpress_add_error "${errors_name}" "dependency" "WP_CLI_UNAVAILABLE" "Configured WP-CLI executable was not found for ${name}."
    fi

    if [[ "${wp_cli_available}" == "true" ]]; then
        if mst_wordpress_wp_cli_run "${wp_cli_path}" "${document_root}" "${site_url}" "${MST_WORDPRESS_TIMEOUT_SECONDS}" core is-installed; then
            core_installed="true"
        else
            status="critical"
            severity="critical"
            mst_wordpress_add_error "${errors_name}" "dependency" "WORDPRESS_NOT_INSTALLED" "WordPress core is not installed for ${name}."
        fi

        if [[ "${core_installed}" == "true" ]]; then
            core_version="$(mst_wordpress_wp_cli_capture "${wp_cli_path}" "${document_root}" "${site_url}" "${MST_WORDPRESS_TIMEOUT_SECONDS}" core version 2>/dev/null || true)"
            core_version="${core_version%$'\r'}"

            core_updates="$(mst_wordpress_parse_count "$(mst_wordpress_wp_cli_capture "${wp_cli_path}" "${document_root}" "${site_url}" "${MST_WORDPRESS_TIMEOUT_SECONDS}" core check-update --format=count 2>/dev/null || printf '0')")"
            if (( core_updates > 0 )) && [[ "${status}" == "ok" ]]; then
                status="warn"
                severity="warning"
            fi

            plugin_csv="$(mst_wordpress_wp_cli_capture "${wp_cli_path}" "${document_root}" "${site_url}" "${MST_WORDPRESS_TIMEOUT_SECONDS}" plugin list --fields=name,status,update --format=csv 2>/dev/null || true)"
            IFS='|' read -r total_plugins active_plugins inactive_plugins plugin_updates <<< "$(mst_wordpress_plugin_counts "${plugin_csv}")"
            if (( plugin_updates > 0 )) && [[ "${status}" == "ok" ]]; then
                status="warn"
                severity="warning"
            fi

            theme_csv="$(mst_wordpress_wp_cli_capture "${wp_cli_path}" "${document_root}" "${site_url}" "${MST_WORDPRESS_TIMEOUT_SECONDS}" theme list --fields=name,status,update --format=csv 2>/dev/null || true)"
            IFS='|' read -r active_theme theme_updates <<< "$(mst_wordpress_theme_info "${theme_csv}")"
            if (( theme_updates > 0 )) && [[ "${status}" == "ok" ]]; then
                status="warn"
                severity="warning"
            fi

            overdue_events="$(mst_wordpress_parse_count "$(mst_wordpress_wp_cli_capture "${wp_cli_path}" "${document_root}" "${site_url}" "${MST_WORDPRESS_TIMEOUT_SECONDS}" cron event list --due-now --format=count 2>/dev/null || printf '0')")"
            if (( overdue_events > 10#${MST_WORDPRESS_CRON_OVERDUE_WARN_COUNT} )) && [[ "${status}" == "ok" ]]; then
                status="warn"
                severity="warning"
            fi

            if mst_wordpress_wp_cli_run "${wp_cli_path}" "${document_root}" "${site_url}" "${MST_WORDPRESS_TIMEOUT_SECONDS}" db check --quiet; then
                db_ok="true"
            else
                status="critical"
                severity="critical"
                mst_wordpress_add_error "${errors_name}" "dependency" "WORDPRESS_DB_CHECK_FAILED" "WordPress database connectivity check failed for ${name}."
            fi

            maintenance_status="$(mst_wordpress_wp_cli_capture "${wp_cli_path}" "${document_root}" "${site_url}" "${MST_WORDPRESS_TIMEOUT_SECONDS}" maintenance-mode status 2>/dev/null || true)"
            maintenance_status="${maintenance_status,,}"
            maintenance_status="${maintenance_status%$'\r'}"
            if [[ "${maintenance_status}" == *"inactive"* ]]; then
                maintenance_status="inactive"
            elif [[ "${maintenance_status}" == *"active"* ]]; then
                maintenance_status="active"
                status="critical"
                severity="critical"
                mst_wordpress_add_error "${errors_name}" "configuration" "WORDPRESS_MAINTENANCE_MODE" "WordPress maintenance mode is active for ${name}."
            else
                maintenance_status="unknown"
            fi
        fi
    fi

    summary="${name} WordPress status collected."
    if [[ "${status}" == "critical" ]]; then
        summary="${name} has a WordPress error condition."
    elif [[ "${status}" == "warn" ]]; then
        summary="${name} has WordPress warnings."
    elif [[ "${status}" == "unavailable" ]]; then
        summary="${name} WordPress monitoring is unavailable."
    fi

    record_ref[status]="${status}"
    record_ref[severity]="${severity}"
    record_ref[target]="${name}"
    record_ref[summary]="${summary}"

    mst_wordpress_add_detail "${details_name}" "site_name" "Site Name" "string" "${name}" "" "false"
    mst_wordpress_add_detail "${details_name}" "site_url" "Site URL" "string" "${site_url}" "" "false"
    if [[ -n "${core_version}" ]]; then
        mst_wordpress_add_detail "${details_name}" "wordpress_version" "WordPress Version" "string" "${core_version}" "" "false"
    else
        mst_wordpress_add_detail "${details_name}" "wordpress_version" "WordPress Version" "null" "null" "" "false"
    fi
    mst_wordpress_add_detail "${details_name}" "wordpress_reachable" "WordPress Reachable" "boolean" "${site_reachable}" "" "false"
    mst_wordpress_add_detail "${details_name}" "wordpress_core_installed" "Core Installed" "boolean" "${core_installed}" "" "false"
    mst_wordpress_add_detail "${details_name}" "core_update_available" "Core Update Available" "boolean" "$([[ "${core_updates}" -gt 0 ]] && printf 'true' || printf 'false')" "" "false"
    mst_wordpress_add_detail "${details_name}" "total_installed_plugins" "Total Installed Plugins" "integer" "${total_plugins}" "" "false"
    mst_wordpress_add_detail "${details_name}" "active_plugins" "Active Plugins" "integer" "${active_plugins}" "" "false"
    mst_wordpress_add_detail "${details_name}" "inactive_plugins" "Inactive Plugins" "integer" "${inactive_plugins}" "" "false"
    mst_wordpress_add_detail "${details_name}" "plugin_updates_available" "Plugin Updates Available" "integer" "${plugin_updates}" "" "false"
    if [[ -n "${active_theme}" ]]; then
        mst_wordpress_add_detail "${details_name}" "active_theme" "Active Theme" "string" "${active_theme}" "" "false"
    else
        mst_wordpress_add_detail "${details_name}" "active_theme" "Active Theme" "null" "null" "" "false"
    fi
    mst_wordpress_add_detail "${details_name}" "theme_updates_available" "Theme Updates Available" "integer" "${theme_updates}" "" "false"
    mst_wordpress_add_detail "${details_name}" "rest_api_reachable" "REST API Reachable" "boolean" "${rest_reachable}" "" "false"
    mst_wordpress_add_detail "${details_name}" "rest_api_status" "REST API Status" "integer" "${rest_status:-0}" "" "false"
    mst_wordpress_add_detail "${details_name}" "wp_cron_enabled" "WP-Cron Enabled" "boolean" "${cron_enabled}" "" "false"
    mst_wordpress_add_detail "${details_name}" "overdue_scheduled_events" "Overdue Scheduled Events" "integer" "${overdue_events}" "" "false"
    mst_wordpress_add_detail "${details_name}" "database_connectivity" "Database Connectivity" "boolean" "${db_ok}" "" "false"
    mst_wordpress_add_detail "${details_name}" "debug_mode_enabled" "Debug Mode Enabled" "string" "${debug_mode}" "" "false"
    mst_wordpress_add_detail "${details_name}" "maintenance_mode" "Maintenance Mode" "string" "${maintenance_status}" "" "false"

    mst_wordpress_add_row "${rows_name}" "Name" "${name}"
    mst_wordpress_add_row "${rows_name}" "URL" "${site_url}"
    mst_wordpress_add_row "${rows_name}" "WordPress Version" "${core_version:-n/a}"
    mst_wordpress_add_row "${rows_name}" "WordPress Reachable" "${site_reachable}"
    mst_wordpress_add_row "${rows_name}" "Core Installed" "${core_installed}"
    mst_wordpress_add_row "${rows_name}" "Core Updates" "${core_updates}"
    mst_wordpress_add_row "${rows_name}" "Total Plugins" "${total_plugins}"
    mst_wordpress_add_row "${rows_name}" "Active Plugins" "${active_plugins}"
    mst_wordpress_add_row "${rows_name}" "Inactive Plugins" "${inactive_plugins}"
    mst_wordpress_add_row "${rows_name}" "Plugin Updates" "${plugin_updates}"
    mst_wordpress_add_row "${rows_name}" "Active Theme" "${active_theme:-n/a}"
    mst_wordpress_add_row "${rows_name}" "Theme Updates" "${theme_updates}"
    mst_wordpress_add_row "${rows_name}" "REST API Reachable" "${rest_reachable}"
    mst_wordpress_add_row "${rows_name}" "REST API Status" "${rest_status:-0}"
    mst_wordpress_add_row "${rows_name}" "WP-Cron Enabled" "${cron_enabled}"
    mst_wordpress_add_row "${rows_name}" "Overdue Events" "${overdue_events}"
    mst_wordpress_add_row "${rows_name}" "Database Connectivity" "${db_ok}"
    mst_wordpress_add_row "${rows_name}" "Debug Mode" "${debug_mode}"
    mst_wordpress_add_row "${rows_name}" "Maintenance Mode" "${maintenance_status}"
    mst_wordpress_record_finalize "${record_name}" "${started_ms}"
}
