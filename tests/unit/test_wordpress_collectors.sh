#!/usr/bin/env bash
# Validate WordPress collectors with mocked WP-CLI, REST, and config inspection.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/wordpress-collectors"
PROC_DIR="${TMP_DIR}/proc"
SITE_DIR="${TMP_DIR}/site"
mkdir -p "${PROC_DIR}/sys/kernel" "${SITE_DIR}"

cat > "${PROC_DIR}/sys/kernel/hostname" <<'EOF'
wordpress-test
EOF

cat > "${SITE_DIR}/wp-config.php" <<'EOF'
<?php
define( 'WP_DEBUG', false );
define( 'DISABLE_WP_CRON', false );
EOF

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/inspectors/wordpress.sh"

export MST_WORDPRESS_CRON_OVERDUE_WARN_COUNT="0"

WP_BIN_DIR="${TMP_DIR}/bin"
WP_ARG_LOG="${TMP_DIR}/wp-args.log"
mkdir -p "${WP_BIN_DIR}"
cat > "${WP_BIN_DIR}/wp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "${MST_TEST_WP_ARG_LOG:?arg log required}"
for arg in "$@"; do
    if [[ "${arg}" == "--allow-root" ]]; then
        exit 0
    fi
done
if [[ "${MST_TEST_EXPECT_ALLOW_ROOT:-0}" -eq 1 ]]; then
    exit 1
fi
exit 0
EOF
chmod 0755 "${WP_BIN_DIR}/wp"

ORIGINAL_PATH="${PATH}"
PATH="${WP_BIN_DIR}:${PATH}"
export PATH MST_TEST_WP_ARG_LOG="${WP_ARG_LOG}"
: > "${WP_ARG_LOG}"
if [[ "${EUID}" -eq 0 ]]; then
    export MST_TEST_EXPECT_ALLOW_ROOT=1
    mst_wordpress_wp_cli_run "wp" "${SITE_DIR}" "https://example.test" "5" core is-installed || {
        printf 'wp-cli run should pass --allow-root when invoked as root.\n' >&2
        exit 1
    }
    mst_wordpress_wp_cli_capture "wp" "${SITE_DIR}" "https://example.test" "5" core version >/dev/null || {
        printf 'wp-cli capture should pass --allow-root when invoked as root.\n' >&2
        exit 1
    }
    grep -q -- '--allow-root' "${WP_ARG_LOG}" || {
        printf 'wp-cli invocation did not include --allow-root for root execution.\n' >&2
        exit 1
    }
else
    export MST_TEST_EXPECT_ALLOW_ROOT=0
    mst_wordpress_wp_cli_run "wp" "${SITE_DIR}" "https://example.test" "5" core is-installed || exit 1
    if grep -q -- '--allow-root' "${WP_ARG_LOG}"; then
        printf 'wp-cli invocation should not include --allow-root for non-root execution.\n' >&2
        exit 1
    fi
fi
PATH="${ORIGINAL_PATH}"
export PATH
unset MST_TEST_EXPECT_ALLOW_ROOT

mst_wordpress_detect_hostname() {
    printf 'wordpress-test'
}

mst_command_exists() {
    case "${1}" in
        curl|wp) return 0 ;;
        *) command -v "${1}" >/dev/null 2>&1 ;;
    esac
}

mst_wordpress_wp_cli_exists() {
    [[ "${1}" == "wp" ]]
}

mst_wordpress_site_probe() {
    case "${1}" in
        https://example.test)
            printf 'url_effective=https://example.test/\nresponse_code=200\ntime_total=0.100\ntime_connect=0.010\nnum_redirects=0\ncontent_type=text/html\nsize_download=42\nremote_ip=127.0.0.1\nssl_verify_result=0\n'
            ;;
        https://rest-down.test)
            printf 'url_effective=https://rest-down.test/\nresponse_code=200\ntime_total=0.100\ntime_connect=0.010\nnum_redirects=0\ncontent_type=text/html\nsize_download=42\nremote_ip=127.0.0.1\nssl_verify_result=0\n'
            ;;
        https://db-fail.test)
            printf 'url_effective=https://db-fail.test/\nresponse_code=200\ntime_total=0.100\ntime_connect=0.010\nnum_redirects=0\ncontent_type=text/html\nsize_download=42\nremote_ip=127.0.0.1\nssl_verify_result=0\n'
            ;;
        https://missing.test)
            printf 'url_effective=https://missing.test/\nresponse_code=200\ntime_total=0.100\ntime_connect=0.010\nnum_redirects=0\ncontent_type=text/html\nsize_download=42\nremote_ip=127.0.0.1\nssl_verify_result=0\n'
            ;;
        https://cli-missing.test)
            printf 'url_effective=https://cli-missing.test/\nresponse_code=200\ntime_total=0.100\ntime_connect=0.010\nnum_redirects=0\ncontent_type=text/html\nsize_download=42\nremote_ip=127.0.0.1\nssl_verify_result=0\n'
            ;;
        *)
            return 1
            ;;
    esac
}

mst_wordpress_rest_probe() {
    case "${1}" in
        https://rest-down.test)
            return 7
            ;;
        *)
            printf 'url_effective=%s/wp-json/\nresponse_code=200\ntime_total=0.050\ntime_connect=0.010\nnum_redirects=0\ncontent_type=application/json\nsize_download=100\nremote_ip=127.0.0.1\nssl_verify_result=0\n' "${1%/}"
            ;;
    esac
}

mst_wordpress_wp_cli_capture() {
    local wp_cli_path="${1}"
    local _document_root="${2}"
    local site_url="${3}"
    local _timeout_seconds="${4}"
    shift 4 || true
    local command_key="$*"

    if [[ "${wp_cli_path}" != "wp" ]]; then
        return 127
    fi

    case "${site_url}|${command_key}" in
        "https://example.test|core version") printf '6.6.0\n' ;;
        "https://example.test|core check-update --format=count") printf '0\n' ;;
        "https://example.test|plugin list --fields=name,status,update --format=csv") printf 'name,status,update\nakismet,active,none\nseo,inactive,none\n' ;;
        "https://example.test|theme list --fields=name,status,update --format=csv") printf 'name,status,update\ntwentytwentyfour,active,none\n' ;;
        "https://example.test|cron event list --due-now --format=count") printf '0\n' ;;
        "https://example.test|maintenance-mode status") printf 'inactive\n' ;;

        "https://rest-down.test|core version") printf '6.6.0\n' ;;
        "https://rest-down.test|core check-update --format=count") printf '0\n' ;;
        "https://rest-down.test|plugin list --fields=name,status,update --format=csv") printf 'name,status,update\nakismet,active,none\n' ;;
        "https://rest-down.test|theme list --fields=name,status,update --format=csv") printf 'name,status,update\ntwentytwentyfour,active,none\n' ;;
        "https://rest-down.test|cron event list --due-now --format=count") printf '0\n' ;;
        "https://rest-down.test|maintenance-mode status") printf 'inactive\n' ;;

        "https://db-fail.test|core version") printf '6.6.0\n' ;;
        "https://db-fail.test|core check-update --format=count") printf '0\n' ;;
        "https://db-fail.test|plugin list --fields=name,status,update --format=csv") printf 'name,status,update\nakismet,active,none\n' ;;
        "https://db-fail.test|theme list --fields=name,status,update --format=csv") printf 'name,status,update\ntwentytwentyfour,active,none\n' ;;
        "https://db-fail.test|cron event list --due-now --format=count") printf '0\n' ;;
        "https://db-fail.test|maintenance-mode status") printf 'inactive\n' ;;

        "https://missing.test|core version") printf '' ;;
        "https://updates.test|core version") printf '6.6.0\n' ;;
        "https://updates.test|core check-update --format=count") printf '1\n' ;;
        "https://updates.test|plugin list --fields=name,status,update --format=csv") printf 'name,status,update\nakismet,active,available\nseo,inactive,none\n' ;;
        "https://updates.test|theme list --fields=name,status,update --format=csv") printf 'name,status,update\ntwentytwentyfour,active,available\n' ;;
        "https://updates.test|cron event list --due-now --format=count") printf '3\n' ;;
        "https://updates.test|maintenance-mode status") printf 'active\n' ;;
        *)
            return 1
            ;;
    esac
}

mst_wordpress_wp_cli_run() {
    local wp_cli_path="${1}"
    local _document_root="${2}"
    local site_url="${3}"
    local _timeout_seconds="${4}"
    shift 4 || true
    local command_key="$*"

    if [[ "${wp_cli_path}" != "wp" ]]; then
        return 127
    fi

    case "${site_url}|${command_key}" in
        "https://example.test|core is-installed") return 0 ;;
        "https://example.test|db check --quiet") return 0 ;;
        "https://rest-down.test|core is-installed") return 0 ;;
        "https://rest-down.test|db check --quiet") return 0 ;;
        "https://db-fail.test|core is-installed") return 0 ;;
        "https://db-fail.test|db check --quiet") return 1 ;;
        "https://missing.test|core is-installed") return 1 ;;
        "https://updates.test|core is-installed") return 0 ;;
        "https://updates.test|db check --quiet") return 0 ;;
        *) return 1 ;;
    esac
}

declare -A ok_record=()
declare -a ok_details=() ok_errors=() ok_rows=()
mst_wordpress_collect_site 1 "Main WP" "https://example.test" "${SITE_DIR}" "${SITE_DIR}/wp-config.php" "wp" "true" ok_record ok_details ok_errors ok_rows
[[ "${ok_record[status]}" == "ok" ]] || exit 1

declare -A missing_record=()
declare -a missing_details=() missing_errors=() missing_rows=()
mst_wordpress_collect_site 2 "Missing WP" "https://missing.test" "${SITE_DIR}" "${SITE_DIR}/wp-config.php" "wp" "true" missing_record missing_details missing_errors missing_rows
[[ "${missing_record[status]}" == "critical" ]] || exit 1

declare -A cli_missing_record=()
declare -a cli_missing_details=() cli_missing_errors=() cli_missing_rows=()
mst_wordpress_collect_site 3 "CLI Missing" "https://cli-missing.test" "${SITE_DIR}" "${SITE_DIR}/wp-config.php" "wp-missing" "true" cli_missing_record cli_missing_details cli_missing_errors cli_missing_rows
[[ "${cli_missing_record[status]}" == "unavailable" ]] || exit 1

declare -A rest_down_record=()
declare -a rest_down_details=() rest_down_errors=() rest_down_rows=()
mst_wordpress_collect_site 4 "REST Down" "https://rest-down.test" "${SITE_DIR}" "${SITE_DIR}/wp-config.php" "wp" "true" rest_down_record rest_down_details rest_down_errors rest_down_rows
[[ "${rest_down_record[status]}" == "warn" ]] || exit 1

declare -A db_fail_record=()
declare -a db_fail_details=() db_fail_errors=() db_fail_rows=()
mst_wordpress_collect_site 5 "DB Fail" "https://db-fail.test" "${SITE_DIR}" "${SITE_DIR}/wp-config.php" "wp" "true" db_fail_record db_fail_details db_fail_errors db_fail_rows
[[ "${db_fail_record[status]}" == "critical" ]] || exit 1

cat > "${SITE_DIR}/wp-config.php" <<'EOF'
<?php
define( 'WP_DEBUG', true );
define( 'DISABLE_WP_CRON', false );
EOF

mst_wordpress_site_probe() {
    case "${1}" in
        https://updates.test)
            printf 'url_effective=https://updates.test/\nresponse_code=200\ntime_total=0.100\ntime_connect=0.010\nnum_redirects=0\ncontent_type=text/html\nsize_download=42\nremote_ip=127.0.0.1\nssl_verify_result=0\n'
            ;;
        *)
            printf 'url_effective=%s/\nresponse_code=200\ntime_total=0.100\ntime_connect=0.010\nnum_redirects=0\ncontent_type=text/html\nsize_download=42\nremote_ip=127.0.0.1\nssl_verify_result=0\n' "${1%/}"
            ;;
    esac
}

mst_wordpress_rest_probe() {
    printf 'url_effective=%s/wp-json/\nresponse_code=200\ntime_total=0.050\ntime_connect=0.010\nnum_redirects=0\ncontent_type=application/json\nsize_download=100\nremote_ip=127.0.0.1\nssl_verify_result=0\n' "${1%/}"
}

declare -A updates_record=()
declare -a updates_details=() updates_errors=() updates_rows=()
mst_wordpress_collect_site 6 "Updates WP" "https://updates.test" "${SITE_DIR}" "${SITE_DIR}/wp-config.php" "wp" "true" updates_record updates_details updates_errors updates_rows
[[ "${updates_record[status]}" == "critical" ]] || exit 1
[[ "${updates_record[summary]}" == *"error condition"* ]] || exit 1

cat > "${SITE_DIR}/wp-config.php" <<'EOF'
<?php
define( 'WP_DEBUG', false );
define( 'DISABLE_WP_CRON', false );
EOF

printf 'test_wordpress_collectors.sh passed.\n'
