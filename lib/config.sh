#!/usr/bin/env bash
# MST layered configuration loading and validation.

# Apply the built-in default configuration values.
mst_config_apply_defaults() {
    export MST_CONFIG_SCHEMA_VERSION="${MST_SUPPORTED_CONFIG_SCHEMA_VERSION}"
    export MST_CONFIG_FILE="${MST_CONFIG_FILE:-/etc/mst/config.conf}"
    export MST_LOG_LEVEL="INFO"
    export MST_OUTPUT_MODE="${MST_OUTPUT_MODE:-text}"
    export MST_COLOR_MODE="auto"
    export MST_LOG_DIR="/var/log/mst"
    export MST_STATE_DIR="/var/lib/mst"
    export MST_LOCK_DIR="${MST_STATE_DIR}/locks"
    export MST_VERBOSE="0"
    export MST_TIMEOUT_SECONDS="${MST_DEFAULT_TIMEOUT_SECONDS}"
    export MST_ALLOW_ENV_OVERRIDES="yes"
    export MST_HEALTH_CPU_WARN_PERCENT="80"
    export MST_HEALTH_CPU_ERROR_PERCENT="95"
    export MST_HEALTH_MEMORY_WARN_PERCENT="85"
    export MST_HEALTH_MEMORY_ERROR_PERCENT="95"
    export MST_HEALTH_DISK_WARN_PERCENT="85"
    export MST_HEALTH_DISK_ERROR_PERCENT="95"
    export MST_SERVICES_NGINX_CANDIDATES="nginx.service"
    export MST_SERVICES_PHP_FPM_CANDIDATES="php8.3-fpm.service,php8.2-fpm.service,php8.1-fpm.service,php8.0-fpm.service,php7.4-fpm.service,php-fpm.service"
    export MST_SERVICES_DATABASE_CANDIDATES="mariadb.service,mysql.service"
    export MST_SERVICES_REDIS_CANDIDATES="redis-server.service"
    export MST_SERVICES_CRON_CANDIDATES="cron.service,crond.service"
    export MST_SERVICES_FAIL2BAN_CANDIDATES="fail2ban.service"
    export MST_SERVICES_SSH_CANDIDATES="ssh.service,sshd.service"
    export MST_SECURITY_PROC_DIR="/proc"
    export MST_SECURITY_SSH_SERVICE_CANDIDATES="ssh.service,sshd.service"
    export MST_SECURITY_SSH_CONFIG_FILE="/etc/ssh/sshd_config"
    export MST_SECURITY_UFW_CONF_FILE="/etc/ufw/ufw.conf"
    export MST_SECURITY_UFW_DEFAULTS_FILE="/etc/default/ufw"
    export MST_SECURITY_FAIL2BAN_SERVICE_CANDIDATES="fail2ban.service"
    export MST_SECURITY_AUTO_UPGRADES_FILE="/etc/apt/apt.conf.d/20auto-upgrades"
    export MST_SECURITY_TIMESYNC_SERVICE_CANDIDATES="systemd-timesyncd.service,chrony.service,chronyd.service,ntp.service"
    export MST_WEBSITE_TARGETS=""
    export MST_WEBSITE_AUTO_DISCOVER="no"
    export MST_WEBSITE_RESPONSE_WARN_MS="2000"
    export MST_WEBSITE_TLS_EXPIRY_WARN_DAYS="14"
    export MST_WEBSITE_REDIRECT_WARN_COUNT="0"
    export MST_WORDPRESS_TARGETS=""
    export MST_WORDPRESS_AUTO_DISCOVER="no"
    export MST_WORDPRESS_CRON_OVERDUE_WARN_COUNT="0"
    export MST_BACKUP_TARGETS=""
    export MST_TELEGRAM_ENABLED="false"
    export MST_TELEGRAM_BOT_TOKEN=""
    export MST_TELEGRAM_CHAT_ID=""
    export MST_TELEGRAM_PARSE_MODE=""
    export MST_TELEGRAM_DISABLE_WEB_PAGE_PREVIEW="true"
    export MST_TELEGRAM_TIMEOUT_SECONDS="15"
    export MST_TELEGRAM_MAX_RETRIES="2"
    export MST_TELEGRAM_RETRY_DELAY_SECONDS="2"
    export MST_ALERTS_ENABLED="false"
    export MST_ALERT_ON_WARNING="true"
    export MST_ALERT_ON_ERROR="true"
    export MST_ALERT_ON_UNAVAILABLE="true"
    export MST_ALERT_ON_UNKNOWN="true"
    export MST_ALERT_MODULES="all"
    export MST_ALERT_COOLDOWN_SECONDS="3600"
    export MST_ALERT_RECOVERY_ENABLED="true"
    export MST_ALERT_REPEAT_ENABLED="false"
    export MST_ALERT_REPEAT_INTERVAL_SECONDS="21600"
}

# Load one configuration file if it exists.
mst_config_load_file() {
    local file_path="${1:?file path required}"
    local line trimmed key value

    if [[ ! -f "${file_path}" ]]; then
        return 0
    fi

    mst_fs_validate_trusted_config_file "${file_path}" || mst_die "${MST_EXIT_SECURITY}" "Unsafe configuration file: ${file_path}"

    while IFS= read -r line || [[ -n "${line}" ]]; do
        trimmed="${line%$'\r'}"
        [[ "${trimmed}" =~ ^[[:space:]]*$ ]] && continue
        [[ "${trimmed}" =~ ^[[:space:]]*# ]] && continue

        if [[ "${trimmed}" =~ ^[[:space:]]*(MST_[A-Z0-9_]+)[[:space:]]*=[[:space:]]*\"([^\"]*)\"[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
        elif [[ "${trimmed}" =~ ^[[:space:]]*(MST_[A-Z0-9_]+)[[:space:]]*=[[:space:]]*\'([^\']*)\'[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
        elif [[ "${trimmed}" =~ ^[[:space:]]*(MST_[A-Z0-9_]+)[[:space:]]*=[[:space:]]*([^[:space:]#]+)[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
        else
            mst_die "${MST_EXIT_SECURITY}" "Unsupported configuration syntax in ${file_path}"
        fi

        case "${key}" in
            MST_CONFIG_SCHEMA_VERSION|MST_LOG_LEVEL|MST_OUTPUT_MODE|MST_COLOR_MODE|MST_LOG_DIR|MST_STATE_DIR|MST_LOCK_DIR|MST_TIMEOUT_SECONDS|MST_ALLOW_ENV_OVERRIDES|MST_HEALTH_CPU_WARN_PERCENT|MST_HEALTH_CPU_ERROR_PERCENT|MST_HEALTH_MEMORY_WARN_PERCENT|MST_HEALTH_MEMORY_ERROR_PERCENT|MST_HEALTH_DISK_WARN_PERCENT|MST_HEALTH_DISK_ERROR_PERCENT|MST_SERVICES_NGINX_CANDIDATES|MST_SERVICES_PHP_FPM_CANDIDATES|MST_SERVICES_DATABASE_CANDIDATES|MST_SERVICES_REDIS_CANDIDATES|MST_SERVICES_CRON_CANDIDATES|MST_SERVICES_FAIL2BAN_CANDIDATES|MST_SERVICES_SSH_CANDIDATES|MST_SECURITY_PROC_DIR|MST_SECURITY_SSH_SERVICE_CANDIDATES|MST_SECURITY_SSH_CONFIG_FILE|MST_SECURITY_UFW_CONF_FILE|MST_SECURITY_UFW_DEFAULTS_FILE|MST_SECURITY_FAIL2BAN_SERVICE_CANDIDATES|MST_SECURITY_AUTO_UPGRADES_FILE|MST_SECURITY_TIMESYNC_SERVICE_CANDIDATES|MST_WEBSITE_TARGETS|MST_WEBSITE_AUTO_DISCOVER|MST_WEBSITE_RESPONSE_WARN_MS|MST_WEBSITE_TLS_EXPIRY_WARN_DAYS|MST_WEBSITE_REDIRECT_WARN_COUNT|MST_WORDPRESS_TARGETS|MST_WORDPRESS_AUTO_DISCOVER|MST_WORDPRESS_CRON_OVERDUE_WARN_COUNT|MST_BACKUP_TARGETS|MST_TELEGRAM_ENABLED|MST_TELEGRAM_BOT_TOKEN|MST_TELEGRAM_CHAT_ID|MST_TELEGRAM_PARSE_MODE|MST_TELEGRAM_DISABLE_WEB_PAGE_PREVIEW|MST_TELEGRAM_TIMEOUT_SECONDS|MST_TELEGRAM_MAX_RETRIES|MST_TELEGRAM_RETRY_DELAY_SECONDS|MST_ALERTS_ENABLED|MST_ALERT_ON_WARNING|MST_ALERT_ON_ERROR|MST_ALERT_ON_UNAVAILABLE|MST_ALERT_ON_UNKNOWN|MST_ALERT_MODULES|MST_ALERT_COOLDOWN_SECONDS|MST_ALERT_RECOVERY_ENABLED|MST_ALERT_REPEAT_ENABLED|MST_ALERT_REPEAT_INTERVAL_SECONDS)
                printf -v "${key}" '%s' "${value}"
                export "${key}"
                ;;
            *)
                mst_die "${MST_EXIT_SECURITY}" "Unsupported configuration key in ${file_path}: ${key}"
                ;;
        esac
    done < "${file_path}"
}

# Load any layered drop-in configuration files.
mst_config_load_drop_ins() {
    local drop_in
    for drop_in in /etc/mst/conf.d/*.conf; do
        [[ -e "${drop_in}" ]] || continue
        mst_config_load_file "${drop_in}"
    done
}

# Apply approved environment overrides only.
mst_config_apply_environment_overrides() {
    if [[ "${MST_ALLOW_ENV_OVERRIDES}" != "yes" ]]; then
        return 0
    fi

    if [[ -n "${MST_ENV_LOG_LEVEL:-}" ]]; then
        export MST_LOG_LEVEL="${MST_ENV_LOG_LEVEL}"
    fi

    if [[ -n "${MST_ENV_OUTPUT_MODE:-}" ]]; then
        export MST_OUTPUT_MODE="${MST_ENV_OUTPUT_MODE}"
    fi

    if [[ -n "${MST_ENV_TIMEOUT_SECONDS:-}" ]]; then
        export MST_TIMEOUT_SECONDS="${MST_ENV_TIMEOUT_SECONDS}"
    fi

    if [[ -n "${MST_ENV_VERBOSE:-}" ]]; then
        export MST_VERBOSE="${MST_ENV_VERBOSE}"
    fi
}

# Validate the effective configuration and fail safely on invalid values.
mst_config_validate() {
    mst_validate_schema_version "${MST_CONFIG_SCHEMA_VERSION:-}" || mst_die "${MST_EXIT_USAGE}" "Unsupported config schema version"
    mst_validate_log_level "${MST_LOG_LEVEL:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid log level in configuration"
    mst_validate_output_mode "${MST_OUTPUT_MODE:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid output mode in configuration"
    mst_validate_non_negative_integer "${MST_TIMEOUT_SECONDS:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid timeout value in configuration"
    mst_validate_absolute_path "${MST_LOG_DIR:-}" || mst_die "${MST_EXIT_USAGE}" "MST_LOG_DIR must be absolute"
    mst_validate_absolute_path "${MST_STATE_DIR:-}" || mst_die "${MST_EXIT_USAGE}" "MST_STATE_DIR must be absolute"
    mst_validate_absolute_path "${MST_LOCK_DIR:-}" || mst_die "${MST_EXIT_USAGE}" "MST_LOCK_DIR must be absolute"
    mst_validate_percentage "${MST_HEALTH_CPU_WARN_PERCENT:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid CPU warning threshold"
    mst_validate_percentage "${MST_HEALTH_CPU_ERROR_PERCENT:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid CPU error threshold"
    mst_validate_percentage "${MST_HEALTH_MEMORY_WARN_PERCENT:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid memory warning threshold"
    mst_validate_percentage "${MST_HEALTH_MEMORY_ERROR_PERCENT:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid memory error threshold"
    mst_validate_percentage "${MST_HEALTH_DISK_WARN_PERCENT:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid disk warning threshold"
    mst_validate_percentage "${MST_HEALTH_DISK_ERROR_PERCENT:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid disk error threshold"
    (( 10#${MST_HEALTH_CPU_WARN_PERCENT} < 10#${MST_HEALTH_CPU_ERROR_PERCENT} )) || mst_die "${MST_EXIT_USAGE}" "CPU warning threshold must be lower than error threshold"
    (( 10#${MST_HEALTH_MEMORY_WARN_PERCENT} < 10#${MST_HEALTH_MEMORY_ERROR_PERCENT} )) || mst_die "${MST_EXIT_USAGE}" "Memory warning threshold must be lower than error threshold"
    (( 10#${MST_HEALTH_DISK_WARN_PERCENT} < 10#${MST_HEALTH_DISK_ERROR_PERCENT} )) || mst_die "${MST_EXIT_USAGE}" "Disk warning threshold must be lower than error threshold"
    mst_validate_non_negative_integer "${MST_WEBSITE_RESPONSE_WARN_MS:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid website response warning threshold"
    mst_validate_non_negative_integer "${MST_WEBSITE_TLS_EXPIRY_WARN_DAYS:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid website TLS expiry warning threshold"
    mst_validate_non_negative_integer "${MST_WEBSITE_REDIRECT_WARN_COUNT:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid website redirect warning threshold"
    mst_validate_boolean_flag "${MST_WEBSITE_AUTO_DISCOVER:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid website auto-discover flag"
    mst_validate_website_targets "${MST_WEBSITE_TARGETS:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid website target configuration"
    mst_validate_non_negative_integer "${MST_WORDPRESS_CRON_OVERDUE_WARN_COUNT:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid WordPress cron overdue warning threshold"
    mst_validate_boolean_flag "${MST_WORDPRESS_AUTO_DISCOVER:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid WordPress auto-discover flag"
    mst_validate_wordpress_targets "${MST_WORDPRESS_TARGETS:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid WordPress target configuration"
    mst_validate_backup_targets "${MST_BACKUP_TARGETS:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid backup target configuration"
    mst_validate_boolean_flag "${MST_TELEGRAM_ENABLED:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid Telegram enabled flag"
    mst_validate_telegram_parse_mode "${MST_TELEGRAM_PARSE_MODE:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid Telegram parse mode"
    mst_validate_boolean_flag "${MST_TELEGRAM_DISABLE_WEB_PAGE_PREVIEW:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid Telegram web preview flag"
    mst_validate_positive_integer "${MST_TELEGRAM_TIMEOUT_SECONDS:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid Telegram timeout"
    mst_validate_non_negative_integer "${MST_TELEGRAM_MAX_RETRIES:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid Telegram retry count"
    mst_validate_non_negative_integer "${MST_TELEGRAM_RETRY_DELAY_SECONDS:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid Telegram retry delay"
    if [[ "${MST_TELEGRAM_ENABLED}" == "true" ]] || [[ "${MST_TELEGRAM_ENABLED}" == "yes" ]] || [[ "${MST_TELEGRAM_ENABLED}" == "1" ]]; then
        mst_validate_telegram_bot_token "${MST_TELEGRAM_BOT_TOKEN:-}" || mst_die "${MST_EXIT_USAGE}" "Telegram bot token is required when Telegram is enabled"
        mst_validate_telegram_chat_id "${MST_TELEGRAM_CHAT_ID:-}" || mst_die "${MST_EXIT_USAGE}" "Telegram chat ID is required when Telegram is enabled"
    fi
    mst_validate_boolean_flag "${MST_ALERTS_ENABLED:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid alerts enabled flag"
    mst_validate_boolean_flag "${MST_ALERT_ON_WARNING:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid alert warning policy"
    mst_validate_boolean_flag "${MST_ALERT_ON_ERROR:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid alert error policy"
    mst_validate_boolean_flag "${MST_ALERT_ON_UNAVAILABLE:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid alert unavailable policy"
    mst_validate_boolean_flag "${MST_ALERT_ON_UNKNOWN:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid alert unknown policy"
    mst_validate_alert_modules "${MST_ALERT_MODULES:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid alert module filter"
    mst_validate_non_negative_integer "${MST_ALERT_COOLDOWN_SECONDS:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid alert cooldown"
    mst_validate_boolean_flag "${MST_ALERT_RECOVERY_ENABLED:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid alert recovery policy"
    mst_validate_boolean_flag "${MST_ALERT_REPEAT_ENABLED:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid alert repeat policy"
    mst_validate_non_negative_integer "${MST_ALERT_REPEAT_INTERVAL_SECONDS:-}" || mst_die "${MST_EXIT_USAGE}" "Invalid alert repeat interval"
    mst_fs_validate_runtime_write_paths || mst_die "${MST_EXIT_SECURITY}" "Unsafe runtime write configuration"
}

# Load the complete layered configuration set.
mst_config_load() {
    mst_config_apply_defaults
    mst_config_load_file "${MST_CONFIG_FILE}"
    mst_config_load_drop_ins
    mst_config_apply_environment_overrides
    mst_config_validate
}
