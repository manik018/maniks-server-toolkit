#!/usr/bin/env bash
# Shared helpers for the website module.

# shellcheck source=lib/discover.sh
source "${MST_LIB_DIR}/discover.sh"

# Apply default configuration for website collectors.
mst_website_init_defaults() {
    export MST_WEBSITE_TARGETS="${MST_WEBSITE_TARGETS:-}"
    export MST_WEBSITE_AUTO_DISCOVER="${MST_WEBSITE_AUTO_DISCOVER:-no}"
    export MST_WEBSITE_RESPONSE_WARN_MS="${MST_WEBSITE_RESPONSE_WARN_MS:-2000}"
    export MST_WEBSITE_TLS_EXPIRY_WARN_DAYS="${MST_WEBSITE_TLS_EXPIRY_WARN_DAYS:-14}"
    export MST_WEBSITE_REDIRECT_WARN_COUNT="${MST_WEBSITE_REDIRECT_WARN_COUNT:-0}"
}

# Normalize one boolean-like flag to true or false.
mst_website_normalize_boolean() {
    case "${1:-}" in
        1|yes|true) printf 'true' ;;
        *) printf 'false' ;;
    esac
}

# Return the configured website target catalog in normalized form.
mst_website_targets_catalog() {
    local spec="${MST_WEBSITE_TARGETS:-}"
    local entry trimmed name url expected_status timeout_seconds follow_redirects enabled
    local discovered_name _document_root discovered_url
    local old_ifs="${IFS}"
    local -A configured_names=()
    local -A configured_urls=()

    IFS=';'
    for entry in ${spec}; do
        trimmed="${entry#"${entry%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -n "${trimmed}" ]] || continue
        IFS='|' read -r name url expected_status timeout_seconds follow_redirects enabled <<< "${trimmed}"
        [[ -n "${expected_status:-}" ]] || expected_status="200"
        [[ -n "${timeout_seconds:-}" ]] || timeout_seconds="${MST_TIMEOUT_SECONDS:-${MST_DEFAULT_TIMEOUT_SECONDS}}"
        [[ -n "${enabled:-}" ]] || enabled="true"
        configured_names["${name}"]=1
        configured_urls["${url}"]=1
        printf '%s|%s|%s|%s|%s|%s\n' \
            "${name}" \
            "${url}" \
            "${expected_status}" \
            "${timeout_seconds}" \
            "$(mst_website_normalize_boolean "${follow_redirects}")" \
            "$(mst_website_normalize_boolean "${enabled}")"
    done
    IFS="${old_ifs}"

    [[ "$(mst_website_normalize_boolean "${MST_WEBSITE_AUTO_DISCOVER:-no}")" == "true" ]] || return 0
    while IFS='|' read -r discovered_name _document_root || [[ -n "${discovered_name:-}${_document_root:-}" ]]; do
        [[ -n "${discovered_name:-}" ]] || continue
        discovered_url="https://${discovered_name}"
        [[ -z "${configured_names[${discovered_name}]:-}" ]] || continue
        [[ -z "${configured_urls[${discovered_url}]:-}" ]] || continue
        configured_names["${discovered_name}"]=1
        configured_urls["${discovered_url}"]=1
        printf '%s|%s|200|%s|true|true\n' \
            "${discovered_name}" \
            "${discovered_url}" \
            "${MST_TIMEOUT_SECONDS:-${MST_DEFAULT_TIMEOUT_SECONDS}}"
    done < <(mst_discover_web_sites)
}

# Parse a simple HTTP or HTTPS URL into scheme, host, port, and path.
mst_website_parse_url() {
    local url="${1:?url required}"
    local scheme host port path remainder

    [[ "${url}" =~ ^(https?)://([^/]+)(/.*)?$ ]] || return 1
    scheme="${BASH_REMATCH[1]}"
    remainder="${BASH_REMATCH[2]}"
    path="${BASH_REMATCH[3]:-/}"

    if [[ "${remainder}" == *:* ]]; then
        host="${remainder%%:*}"
        port="${remainder##*:}"
    else
        host="${remainder}"
        if [[ "${scheme}" == "https" ]]; then
            port="443"
        else
            port="80"
        fi
    fi

    [[ -n "${host}" ]] || return 1
    [[ "${port}" =~ ^[0-9]+$ ]] || return 1
    printf 'scheme=%s\nhost=%s\nport=%s\npath=%s\n' "${scheme}" "${host}" "${port}" "${path}"
}

# Return success if the host string is already an IP literal.
mst_website_host_is_ip_literal() {
    [[ "${1:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Resolve one hostname via getent hosts.
mst_website_dns_lookup() {
    local host_name="${1:?host required}"
    if mst_website_host_is_ip_literal "${host_name}"; then
        printf '%s %s\n' "${host_name}" "${host_name}"
        return 0
    fi
    mst_exec_capture_stdout "${MST_TIMEOUT_SECONDS}" getent hosts "${host_name}"
}

# Probe one website using curl and emit machine-readable key=value output.
mst_website_curl_probe() {
    local url="${1:?url required}"
    local timeout_seconds="${2:?timeout required}"
    local follow_redirects="${3:?follow redirects required}"
    local -a curl_args=(
        -sS
        -o /dev/null
        --connect-timeout "${timeout_seconds}"
        --max-time "${timeout_seconds}"
        --write-out 'url_effective=%{url_effective}\nresponse_code=%{response_code}\ntime_total=%{time_total}\ntime_connect=%{time_connect}\nnum_redirects=%{num_redirects}\ncontent_type=%{content_type}\nsize_download=%{size_download}\nremote_ip=%{remote_ip}\nssl_verify_result=%{ssl_verify_result}\n'
    )

    if [[ "${follow_redirects}" == "true" ]]; then
        curl_args+=( -L )
    fi
    curl_args+=( "${url}" )
    mst_exec_capture_stdout "${timeout_seconds}" curl "${curl_args[@]}"
}

# Read the certificate end date for one TLS endpoint.
mst_website_tls_enddate() {
    local host_name="${1:?host required}"
    local port_number="${2:?port required}"
    local server_name="${3:?server name required}"

    printf '' | openssl s_client -servername "${server_name}" -connect "${host_name}:${port_number}" 2>/dev/null | openssl x509 -noout -enddate
}

# Return days until one openssl enddate string.
mst_website_days_until_enddate() {
    local enddate_line="${1:?enddate line required}"
    local raw_date expires_at now_epoch

    raw_date="${enddate_line#notAfter=}"
    expires_at="$(date -u -d "${raw_date}" '+%s' 2>/dev/null)" || return 1
    now_epoch="$(date -u '+%s')"
    printf '%s' "$(( (expires_at - now_epoch) / 86400 ))"
}

# Format an RFC 2822-like openssl date into YYYY-MM-DD.
mst_website_format_enddate() {
    local enddate_line="${1:?enddate line required}"
    local raw_date

    raw_date="${enddate_line#notAfter=}"
    date -u -d "${raw_date}" '+%Y-%m-%d' 2>/dev/null
}

# Convert seconds with optional decimals to integer milliseconds.
mst_website_seconds_to_ms() {
    local seconds_value="${1:-0}"
    awk -v value="${seconds_value}" 'BEGIN { printf "%d", (value * 1000) + 0.5 }'
}

# Read one key from a key=value payload.
mst_website_payload_value() {
    local payload="${1:-}"
    local key_name="${2:?key required}"
    local line key value

    while IFS= read -r line || [[ -n "${line}" ]]; do
        line="${line%$'\r'}"
        key="${line%%=*}"
        if [[ "${key}" == "${key_name}" ]]; then
            value="${line#*=}"
            printf '%s' "${value}"
            return 0
        fi
    done <<< "${payload}"
    return 1
}

# Return the hostname for aggregate documents.
mst_website_detect_hostname() {
    local hostname_file="/proc/sys/kernel/hostname"
    if [[ -r "${hostname_file}" ]]; then
        tr -d '\n' < "${hostname_file}"
    else
        hostname 2>/dev/null || printf 'localhost'
    fi
}

# Create a stable result identifier fragment from a website name.
mst_website_result_suffix() {
    local name="${1:?name required}"
    local lowered
    lowered="$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]')"
    lowered="$(printf '%s' "${lowered}" | tr -cs 'a-z0-9' '_')"
    lowered="${lowered##_}"
    lowered="${lowered%%_}"
    printf '%s' "${lowered:-site}"
}

# Initialize one website MRRF1 record.
mst_website_record_init() {
    local record_name="${1:?record required}"
    local result_id="${2:?result id required}"
    local target_name="${3:?target required}"
    local provenance="${4:?provenance required}"
    local -n record_ref="${record_name}"

    record_ref[result_id]="${result_id}"
    record_ref[module]="website"
    record_ref[check]="availability"
    record_ref[target]="${target_name}"
    record_ref[status]="unknown"
    record_ref[severity]="unknown"
    record_ref[score]="null"
    record_ref[summary]="Website observation unavailable."
    record_ref[source_list]="curl,openssl,getent"
    record_ref[provenance]="${provenance}"
    record_ref[privilege_requirement]="none"
    record_ref[redactions_present]="false"
}

# Finalize one website record.
mst_website_record_finalize() {
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
mst_website_add_detail() {
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
mst_website_add_row() {
    local rows_name="${1:?rows required}"
    local label="${2:?label required}"
    local value="${3:-}"
    local -n rows_ref="${rows_name}"

    rows_ref+=("$(mst_mrrf_sanitize_text "${label}" 64)${MST_MRRF_FIELD_SEPARATOR}$(mst_mrrf_sanitize_text "${value}" 200)")
}

# Append one MRRF1 error.
mst_website_add_error() {
    local errors_name="${1:?errors required}"
    local category="${2:?category required}"
    local code="${3:?code required}"
    local message="${4:?message required}"
    local -n errors_ref="${errors_name}"

    errors_ref+=("$(mst_mrrf_pack_error "${category}" "${code}" "${message}")")
}

# Mark a website record with a failure state.
mst_website_mark_failure() {
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
    mst_website_add_error "${errors_name}" "${error_category}" "${error_code}" "${error_message}"
}

# Build a generic internal failure record for collector isolation.
mst_website_build_internal_failure_record() {
    local website_index="${1:?index required}"
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
    mst_website_record_init "${record_name}" "res_website.${website_index}.$(mst_website_result_suffix "${name}")" "${name}" "Collector fallback path."
    mst_website_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "${message}" "internal" "COLLECTOR_FAILURE" "${message}"
    mst_website_record_finalize "${record_name}" "${started_ms}"
}

# Return the worst MRRF1 status from a status array.
mst_website_worst_status() {
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
mst_website_worst_severity() {
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

# Return the website command exit code from record statuses.
mst_website_report_exit_code() {
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
mst_website_module_summary_json() {
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

# Collect one configured website target.
mst_website_collect_target() {
    local website_index="${1:?index required}"
    local name="${2:?name required}"
    local url="${3:?url required}"
    local expected_status="${4:?expected status required}"
    local timeout_seconds="${5:?timeout required}"
    local follow_redirects="${6:?follow redirects required}"
    local enabled="${7:?enabled required}"
    local record_name="${8:?record required}"
    local details_name="${9:?details required}"
    local errors_name="${10:?errors required}"
    local rows_name="${11:?rows required}"
    local started_ms dns_output dns_resolved parsed_url host_name scheme_name port_number path_name
    local curl_output curl_exit response_code final_url response_ms redirect_count content_type content_length remote_ip ssl_verify_result connect_ms
    local certificate_present certificate_valid certificate_enddate certificate_days
    local status severity summary http_reachable tcp_success tls_warning="false" slow_warning="false" redirect_warning="false"
    local tls_output
    local -n record_ref="${record_name}"
    local -A url_map=()

    mst_website_init_defaults
    started_ms="$(mst_mrrf_now_epoch_ms)"
    mst_website_record_init "${record_name}" "res_website.${website_index}.$(mst_website_result_suffix "${name}")" "${name}" "Derived from curl, getent hosts, and TLS certificate inspection."

    if [[ "${enabled}" != "true" ]]; then
        mst_website_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "${name} is disabled in configuration." "configuration" "WEBSITE_DISABLED" "Website target ${name} is disabled in configuration."
        mst_website_add_detail "${details_name}" "name" "Name" "string" "${name}" "" "false"
        mst_website_add_detail "${details_name}" "url" "URL" "string" "${url}" "" "false"
        mst_website_add_row "${rows_name}" "Name" "${name}"
        mst_website_add_row "${rows_name}" "URL" "${url}"
        mst_website_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    parsed_url="$(mst_website_parse_url "${url}")" || {
        mst_website_mark_failure "${record_name}" "${errors_name}" "unknown" "unknown" "Website URL could not be parsed." "configuration" "URL_PARSE_FAILED" "Website target ${name} has an invalid URL."
        mst_website_record_finalize "${record_name}" "${started_ms}"
        return 0
    }
    while IFS='=' read -r key value; do
        url_map["${key}"]="${value}"
    done <<< "${parsed_url}"
    scheme_name="${url_map[scheme]}"
    host_name="${url_map[host]}"
    port_number="${url_map[port]}"
    path_name="${url_map[path]}"

    dns_resolved="false"
    if dns_output="$(mst_website_dns_lookup "${host_name}" 2>/dev/null || true)"; then
        if [[ -n "${dns_output}" ]]; then
            dns_resolved="true"
        fi
    fi

    status="ok"
    severity="ok"
    tcp_success="false"
    http_reachable="false"
    final_url="${url}"
    response_code="0"
    response_ms="0"
    redirect_count="0"
    content_type=""
    content_length=""
    remote_ip=""
    ssl_verify_result=""
    connect_ms="0"

    if ! mst_command_exists curl; then
        mst_website_mark_failure "${record_name}" "${errors_name}" "unavailable" "unknown" "${name} could not be checked because curl is unavailable." "dependency" "CURL_NOT_AVAILABLE" "curl command was not found."
        mst_website_record_finalize "${record_name}" "${started_ms}"
        return 0
    fi

    curl_exit=0
    curl_output="$(mst_website_curl_probe "${url}" "${timeout_seconds}" "${follow_redirects}" 2>&1)" || curl_exit=$?

    if [[ "${curl_exit}" -eq 0 ]]; then
        final_url="$(mst_website_payload_value "${curl_output}" "url_effective" || printf '%s' "${url}")"
        response_code="$(mst_website_payload_value "${curl_output}" "response_code" || printf '0')"
        response_ms="$(mst_website_seconds_to_ms "$(mst_website_payload_value "${curl_output}" "time_total" || printf '0')")"
        connect_ms="$(mst_website_seconds_to_ms "$(mst_website_payload_value "${curl_output}" "time_connect" || printf '0')")"
        redirect_count="$(mst_website_payload_value "${curl_output}" "num_redirects" || printf '0')"
        content_type="$(mst_website_payload_value "${curl_output}" "content_type" || true)"
        content_length="$(mst_website_payload_value "${curl_output}" "size_download" || true)"
        remote_ip="$(mst_website_payload_value "${curl_output}" "remote_ip" || true)"
        ssl_verify_result="$(mst_website_payload_value "${curl_output}" "ssl_verify_result" || true)"
        http_reachable="true"
        if [[ -n "${remote_ip}" ]] || (( 10#${connect_ms} > 0 )); then
            tcp_success="true"
        fi
    else
        case "${curl_exit}" in
            6)
                status="critical"
                severity="critical"
                mst_website_add_error "${errors_name}" "network" "DNS_FAILURE" "curl failed to resolve ${host_name}."
                ;;
            7)
                status="critical"
                severity="critical"
                mst_website_add_error "${errors_name}" "network" "TCP_CONNECTION_FAILED" "curl could not connect to ${host_name}:${port_number}."
                ;;
            28)
                status="critical"
                severity="critical"
                mst_website_add_error "${errors_name}" "timeout" "WEBSITE_TIMEOUT" "curl timed out while checking ${url}."
                ;;
            60)
                status="critical"
                severity="critical"
                mst_website_add_error "${errors_name}" "network" "TLS_CERTIFICATE_INVALID" "curl rejected the TLS certificate for ${url}."
                ;;
            *)
                status="critical"
                severity="critical"
                mst_website_add_error "${errors_name}" "network" "CURL_PROBE_FAILED" "$(mst_mrrf_sanitize_text "${curl_output}" 200)"
                ;;
        esac
    fi

    if [[ "${dns_resolved}" != "true" ]]; then
        status="critical"
        severity="critical"
        mst_website_add_error "${errors_name}" "network" "DNS_LOOKUP_FAILED" "getent hosts did not resolve ${host_name}."
    fi

    if [[ "${http_reachable}" == "true" ]]; then
        if [[ "${response_code}" != "${expected_status}" ]]; then
            status="critical"
            severity="critical"
            mst_website_add_error "${errors_name}" "network" "UNEXPECTED_STATUS_CODE" "Expected HTTP status ${expected_status} but received ${response_code} for ${url}."
        fi
        if (( 10#${response_ms} > 10#${MST_WEBSITE_RESPONSE_WARN_MS} )); then
            slow_warning="true"
        fi
        if (( 10#${redirect_count} > 10#${MST_WEBSITE_REDIRECT_WARN_COUNT} )); then
            redirect_warning="true"
        fi
    fi

    certificate_present="false"
    certificate_valid="false"
    certificate_enddate=""
    certificate_days=""
    if [[ "${scheme_name}" == "https" ]] && mst_command_exists openssl; then
        tls_output="$(mst_website_tls_enddate "${host_name}" "${port_number}" "${host_name}" 2>/dev/null || true)"
        if [[ "${tls_output}" == notAfter=* ]]; then
            certificate_present="true"
            certificate_enddate="$(mst_website_format_enddate "${tls_output}" || true)"
            certificate_days="$(mst_website_days_until_enddate "${tls_output}" || true)"
            if [[ -n "${certificate_days}" ]] && (( certificate_days >= 0 )); then
                if [[ "${ssl_verify_result:-0}" == "0" ]] || [[ -z "${ssl_verify_result:-}" ]]; then
                    certificate_valid="true"
                fi
            fi
            if [[ -n "${certificate_days}" ]] && (( certificate_days < 0 )); then
                status="critical"
                severity="critical"
                mst_website_add_error "${errors_name}" "network" "TLS_CERTIFICATE_EXPIRED" "TLS certificate for ${url} is expired."
            elif [[ -n "${certificate_days}" ]] && (( certificate_days <= 10#${MST_WEBSITE_TLS_EXPIRY_WARN_DAYS} )); then
                tls_warning="true"
            fi
        fi
        if [[ "${certificate_present}" != "true" ]]; then
            status="critical"
            severity="critical"
            mst_website_add_error "${errors_name}" "network" "TLS_CERTIFICATE_MISSING" "TLS certificate could not be read for ${url}."
        elif [[ "${certificate_valid}" != "true" ]]; then
            status="critical"
            severity="critical"
            mst_website_add_error "${errors_name}" "network" "TLS_CERTIFICATE_INVALID" "TLS certificate for ${url} is not valid."
        fi
    elif [[ "${scheme_name}" == "https" ]]; then
        mst_website_add_error "${errors_name}" "dependency" "OPENSSL_NOT_AVAILABLE" "openssl command was not found for TLS inspection."
    fi

    if [[ "${status}" == "ok" ]]; then
        if [[ "${tls_warning}" == "true" ]] || [[ "${slow_warning}" == "true" ]] || [[ "${redirect_warning}" == "true" ]]; then
            status="warn"
            severity="warning"
        fi
    fi

    summary="${name} returned ${response_code} from ${final_url} in ${response_ms}ms."
    if [[ "${status}" == "critical" ]]; then
        summary="${name} check failed for ${url}."
    elif [[ "${status}" == "warn" ]]; then
        summary="${name} responded but crossed one or more warning thresholds."
    elif [[ "${status}" == "unavailable" ]]; then
        summary="${name} is unavailable."
    fi

    record_ref[status]="${status}"
    record_ref[severity]="${severity}"
    record_ref[target]="${name}"
    record_ref[summary]="${summary}"

    mst_website_add_detail "${details_name}" "name" "Name" "string" "${name}" "" "false"
    mst_website_add_detail "${details_name}" "url" "URL" "string" "${url}" "" "false"
    mst_website_add_detail "${details_name}" "dns_resolved" "DNS Resolved" "boolean" "${dns_resolved}" "" "false"
    mst_website_add_detail "${details_name}" "tcp_connection_successful" "TCP Connection Successful" "boolean" "${tcp_success}" "" "false"
    mst_website_add_detail "${details_name}" "http_reachable" "HTTP Reachable" "boolean" "${http_reachable}" "" "false"
    mst_website_add_detail "${details_name}" "final_url" "Final URL" "string" "${final_url}" "" "false"
    mst_website_add_detail "${details_name}" "status_code" "Status Code" "integer" "${response_code}" "" "false"
    mst_website_add_detail "${details_name}" "response_time_ms" "Response Time" "integer" "${response_ms}" "milliseconds" "false"
    mst_website_add_detail "${details_name}" "redirect_count" "Redirect Count" "integer" "${redirect_count}" "" "false"
    if [[ "${scheme_name}" == "https" ]]; then
        mst_website_add_detail "${details_name}" "certificate_present" "Certificate Present" "boolean" "${certificate_present}" "" "false"
        mst_website_add_detail "${details_name}" "certificate_valid" "Certificate Valid" "boolean" "${certificate_valid}" "" "false"
        if [[ -n "${certificate_enddate}" ]]; then
            mst_website_add_detail "${details_name}" "certificate_expiration_date" "Certificate Expiration Date" "string" "${certificate_enddate}" "" "false"
        else
            mst_website_add_detail "${details_name}" "certificate_expiration_date" "Certificate Expiration Date" "null" "null" "" "false"
        fi
        if [[ -n "${certificate_days}" ]]; then
            mst_website_add_detail "${details_name}" "days_until_expiration" "Days Until Expiration" "integer" "${certificate_days}" "days" "false"
        else
            mst_website_add_detail "${details_name}" "days_until_expiration" "Days Until Expiration" "null" "null" "" "false"
        fi
    fi
    if [[ -n "${content_length}" ]] && [[ "${content_length}" =~ ^[0-9]+$ ]]; then
        mst_website_add_detail "${details_name}" "content_length" "Content Length" "integer" "${content_length}" "bytes" "false"
    else
        mst_website_add_detail "${details_name}" "content_length" "Content Length" "null" "null" "" "false"
    fi
    if [[ -n "${content_type}" ]]; then
        mst_website_add_detail "${details_name}" "content_type" "Content Type" "string" "${content_type}" "" "false"
    else
        mst_website_add_detail "${details_name}" "content_type" "Content Type" "null" "null" "" "false"
    fi

    mst_website_add_row "${rows_name}" "Name" "${name}"
    mst_website_add_row "${rows_name}" "URL" "${url}"
    mst_website_add_row "${rows_name}" "DNS Resolved" "${dns_resolved}"
    mst_website_add_row "${rows_name}" "TCP Connection" "${tcp_success}"
    mst_website_add_row "${rows_name}" "HTTP Reachable" "${http_reachable}"
    mst_website_add_row "${rows_name}" "Final URL" "${final_url}"
    mst_website_add_row "${rows_name}" "Status Code" "${response_code}"
    mst_website_add_row "${rows_name}" "Response Time" "${response_ms} ms"
    mst_website_add_row "${rows_name}" "Redirect Count" "${redirect_count}"
    if [[ "${scheme_name}" == "https" ]]; then
        mst_website_add_row "${rows_name}" "Certificate Present" "${certificate_present}"
        mst_website_add_row "${rows_name}" "Certificate Valid" "${certificate_valid}"
        mst_website_add_row "${rows_name}" "Certificate Expiry" "${certificate_enddate:-n/a}"
        mst_website_add_row "${rows_name}" "Days Until Expiry" "${certificate_days:-n/a}"
    fi
    mst_website_add_row "${rows_name}" "Content Length" "${content_length:-n/a}"
    mst_website_add_row "${rows_name}" "Content Type" "${content_type:-n/a}"
    mst_website_record_finalize "${record_name}" "${started_ms}"
}
