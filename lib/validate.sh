#!/usr/bin/env bash
# MST validation helpers for config, identifiers, and CLI values.

# Return success if the value is a supported log level.
mst_validate_log_level() {
    case "${1:-}" in
        INFO|WARNING|ERROR|DEBUG) return 0 ;;
        *) return 1 ;;
    esac
}

# Return success if the value is a supported output mode.
mst_validate_output_mode() {
    case "${1:-}" in
        text|json) return 0 ;;
        *) return 1 ;;
    esac
}

# Return success if the value is a non-negative integer.
mst_validate_non_negative_integer() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

# Return success if the value is a positive integer greater than zero.
mst_validate_positive_integer() {
    [[ "${1:-}" =~ ^[0-9]+$ ]] || return 1
    (( 10#${1} > 0 ))
}

# Return success if the value is an integer percentage between 0 and 100.
mst_validate_percentage() {
    [[ "${1:-}" =~ ^[0-9]+$ ]] || return 1
    (( 10#${1} >= 0 && 10#${1} <= 100 ))
}

# Return success if the value is a boolean-like flag.
mst_validate_boolean_flag() {
    case "${1:-}" in
        0|1|yes|no|true|false) return 0 ;;
        *) return 1 ;;
    esac
}

# Return success if the value is a supported Telegram parse mode.
mst_validate_telegram_parse_mode() {
    case "${1:-}" in
        ""|Markdown|MarkdownV2|HTML) return 0 ;;
        *) return 1 ;;
    esac
}

# Return success if the value looks like a Telegram bot token without exposing it.
mst_validate_telegram_bot_token() {
    [[ "${1:-}" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]]
}

# Return success if the value is a Telegram chat id or @channel username.
mst_validate_telegram_chat_id() {
    [[ "${1:-}" =~ ^-?[0-9]+$ ]] || [[ "${1:-}" =~ ^@[A-Za-z0-9_]{5,}$ ]]
}

# Return success if the value is one supported alert module name.
mst_validate_alert_module_name() {
    case "${1:-}" in
        health|services|security|website|wordpress|backup) return 0 ;;
        *) return 1 ;;
    esac
}

# Return success if the value is a comma-separated alert module list.
mst_validate_alert_modules() {
    local value="${1:-}"
    local module_name

    [[ -n "${value}" ]] || return 1
    if [[ "${value}" == "all" ]]; then
        return 0
    fi
    IFS=',' read -r -a modules <<< "${value}"
    for module_name in "${modules[@]}"; do
        [[ -n "${module_name}" ]] || return 1
        mst_validate_alert_module_name "${module_name}" || return 1
    done
    return 0
}

# Return success if the value is a simple HTTP or HTTPS URL.
mst_validate_http_url() {
    [[ "${1:-}" =~ ^https?://[^[:space:]]+$ ]]
}

# Return success if the value is an HTTP status code.
mst_validate_http_status_code() {
    [[ "${1:-}" =~ ^[0-9]{3}$ ]] || return 1
    (( 10#${1} >= 100 && 10#${1} <= 599 ))
}

# Return success if the value is a website display name.
mst_validate_website_name() {
    [[ -n "${1:-}" ]] || return 1
    [[ "${1}" != *"|"* ]] || return 1
    [[ "${1}" != *";"* ]]
}

# Return success if the value is a website target specification list.
mst_validate_website_targets() {
    local spec="${1:-}"
    local entry trimmed name url expected_status timeout_seconds follow_redirects enabled
    local old_ifs="${IFS}"

    [[ -z "${spec}" ]] && return 0

    IFS=';'
    for entry in ${spec}; do
        trimmed="${entry#"${entry%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -n "${trimmed}" ]] || continue
        IFS='|' read -r name url expected_status timeout_seconds follow_redirects enabled <<< "${trimmed}"
        [[ -n "${enabled:-}" ]] || enabled="true"
        [[ -n "${expected_status:-}" ]] || expected_status="200"
        mst_validate_website_name "${name:-}" || {
            IFS="${old_ifs}"
            return 1
        }
        mst_validate_http_url "${url:-}" || {
            IFS="${old_ifs}"
            return 1
        }
        mst_validate_http_status_code "${expected_status}" || {
            IFS="${old_ifs}"
            return 1
        }
        mst_validate_positive_integer "${timeout_seconds:-}" || {
            IFS="${old_ifs}"
            return 1
        }
        mst_validate_boolean_flag "${follow_redirects:-}" || {
            IFS="${old_ifs}"
            return 1
        }
        mst_validate_boolean_flag "${enabled}" || {
            IFS="${old_ifs}"
            return 1
        }
    done
    IFS="${old_ifs}"
    return 0
}

# Return success if the value is a filesystem path or simple executable token.
mst_validate_command_or_path() {
    [[ -n "${1:-}" ]] || return 1
    [[ "${1}" != *"|"* ]] || return 1
    [[ "${1}" != *";"* ]]
}

# Return success if the value is a WordPress target specification list.
mst_validate_wordpress_targets() {
    local spec="${1:-}"
    local entry trimmed name url document_root wp_config_path wp_cli_path enabled
    local old_ifs="${IFS}"

    [[ -z "${spec}" ]] && return 0

    IFS=';'
    for entry in ${spec}; do
        trimmed="${entry#"${entry%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -n "${trimmed}" ]] || continue
        IFS='|' read -r name url document_root wp_config_path wp_cli_path enabled <<< "${trimmed}"
        [[ -n "${wp_cli_path:-}" ]] || wp_cli_path="wp"
        [[ -n "${enabled:-}" ]] || enabled="true"
        mst_validate_website_name "${name:-}" || {
            IFS="${old_ifs}"
            return 1
        }
        mst_validate_http_url "${url:-}" || {
            IFS="${old_ifs}"
            return 1
        }
        if [[ -n "${document_root:-}" ]]; then
            mst_validate_absolute_path "${document_root}" || {
                IFS="${old_ifs}"
                return 1
            }
        fi
        if [[ -n "${wp_config_path:-}" ]]; then
            mst_validate_absolute_path "${wp_config_path}" || {
                IFS="${old_ifs}"
                return 1
            }
        fi
        mst_validate_command_or_path "${wp_cli_path}" || {
            IFS="${old_ifs}"
            return 1
        }
        mst_validate_boolean_flag "${enabled}" || {
            IFS="${old_ifs}"
            return 1
        }
    done
    IFS="${old_ifs}"
    return 0
}

# Return success if the value is one supported backup target type.
mst_validate_backup_target_type() {
    case "${1:-}" in
        local_directory|local_file|rclone_remote) return 0 ;;
        *) return 1 ;;
    esac
}

# Return success if the value is a backup target specification list.
mst_validate_backup_targets() {
    local spec="${1:-}"
    local entry trimmed name target_type location expected_frequency maximum_age_hours minimum_size_mb enabled
    local old_ifs="${IFS}"

    [[ -z "${spec}" ]] && return 0

    IFS=';'
    for entry in ${spec}; do
        trimmed="${entry#"${entry%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -n "${trimmed}" ]] || continue
        IFS='|' read -r name target_type location expected_frequency maximum_age_hours minimum_size_mb enabled <<< "${trimmed}"
        [[ -n "${enabled:-}" ]] || enabled="true"
        mst_validate_website_name "${name:-}" || {
            IFS="${old_ifs}"
            return 1
        }
        mst_validate_backup_target_type "${target_type:-}" || {
            IFS="${old_ifs}"
            return 1
        }
        [[ -n "${location:-}" ]] || {
            IFS="${old_ifs}"
            return 1
        }
        [[ -n "${expected_frequency:-}" ]] || {
            IFS="${old_ifs}"
            return 1
        }
        mst_validate_non_negative_integer "${maximum_age_hours:-}" || {
            IFS="${old_ifs}"
            return 1
        }
        mst_validate_non_negative_integer "${minimum_size_mb:-}" || {
            IFS="${old_ifs}"
            return 1
        }
        mst_validate_boolean_flag "${enabled}" || {
            IFS="${old_ifs}"
            return 1
        }
    done
    IFS="${old_ifs}"
    return 0
}

# Return success if the value is a safe shell identifier fragment.
mst_validate_identifier() {
    [[ "${1:-}" =~ ^[a-z][a-z0-9_-]{0,63}$ ]]
}

# Return success if the config schema version is supported.
mst_validate_schema_version() {
    [[ "${1:-}" == "${MST_SUPPORTED_CONFIG_SCHEMA_VERSION}" ]]
}

# Return success if the value is an absolute path.
mst_validate_absolute_path() {
    [[ "${1:-}" == /* ]]
}

# Return success if the path is safe to use as an MST-owned path.
mst_validate_mst_owned_path() {
    case "${1:-}" in
        /usr/local/bin/mst|/usr/local/lib/mst|/usr/local/lib/mst/*|/etc/mst|/etc/mst/*|/var/log/mst|/var/log/mst/*|/var/lib/mst|/var/lib/mst/*|/etc/logrotate.d/mst)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}
