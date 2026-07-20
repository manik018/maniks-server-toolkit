#!/usr/bin/env bash
# Validate read-only website and WordPress target discovery.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/discovery"
NGINX_DIR="${TMP_DIR}/nginx"
APACHE_DIR="${TMP_DIR}/apache"
WP_ROOT="${TMP_DIR}/www/example"
SHOP_ROOT="${TMP_DIR}/www/shop"

rm -rf -- "${TMP_DIR}"
mkdir -p -- "${NGINX_DIR}/sites-enabled" "${NGINX_DIR}/conf.d" "${APACHE_DIR}" "${WP_ROOT}" "${SHOP_ROOT}"
trap 'rm -rf -- "${TMP_DIR}"' EXIT INT TERM

cat > "${WP_ROOT}/wp-config.php" <<'EOF'
<?php
define('DB_NAME', 'example');
EOF

cat > "${NGINX_DIR}/sites-enabled/example.conf" <<EOF
server {
    listen 80;
    server_name example.com www.example.com;
    root ${WP_ROOT};
}
EOF

cat > "${NGINX_DIR}/sites-enabled/shop.conf" <<EOF
server {
    listen 80;
    server_name shop.example.net;
    root "${SHOP_ROOT}";
}
EOF

cat > "${NGINX_DIR}/sites-enabled/default.conf" <<EOF
server {
    listen 80 default_server;
    server_name _;
    root ${TMP_DIR}/www/default;
}
EOF

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/inspectors/website/common.sh"
source "${ROOT_DIR}/inspectors/wordpress/common.sh"

export MST_DISCOVER_NGINX_DIR="${NGINX_DIR}"
export MST_DISCOVER_APACHE_DIR="${APACHE_DIR}"
export MST_WEBSITE_TARGETS=""
export MST_WEBSITE_AUTO_DISCOVER="no"
export MST_WORDPRESS_TARGETS=""
export MST_WORDPRESS_AUTO_DISCOVER="no"
export MST_TIMEOUT_SECONDS="10"

discovered_sites="$(mst_discover_web_sites)"
expected_sites="$(printf 'example.com|%s\nshop.example.net|%s' "${WP_ROOT}" "${SHOP_ROOT}")"
[[ "${discovered_sites}" == "${expected_sites}" ]] || {
    printf 'unexpected discovered sites:\n%s\n' "${discovered_sites}" >&2
    exit 1
}

mst_discover_site_is_wordpress "${WP_ROOT}" || {
    printf 'expected WordPress root to be detected.\n' >&2
    exit 1
}
if mst_discover_site_is_wordpress "${SHOP_ROOT}"; then
    printf 'non-WordPress root should not be detected.\n' >&2
    exit 1
fi

website_off_output="$(mst_website_targets_catalog)"
[[ -z "${website_off_output}" ]] || {
    printf 'website auto-discovery should be off by default.\n' >&2
    exit 1
}

MST_WEBSITE_AUTO_DISCOVER="yes"
website_auto_output="$(mst_website_targets_catalog)"
expected_website_auto="$(printf 'example.com|https://example.com|200|10|true|true\nshop.example.net|https://shop.example.net|200|10|true|true')"
[[ "${website_auto_output}" == "${expected_website_auto}" ]] || {
    printf 'unexpected website catalog:\n%s\n' "${website_auto_output}" >&2
    exit 1
}

MST_WORDPRESS_AUTO_DISCOVER="yes"
wordpress_auto_output="$(mst_wordpress_targets_catalog)"
expected_wordpress_auto="$(printf 'example.com|https://example.com|%s||wp|true' "${WP_ROOT}")"
[[ "${wordpress_auto_output}" == "${expected_wordpress_auto}" ]] || {
    printf 'unexpected WordPress catalog:\n%s\n' "${wordpress_auto_output}" >&2
    exit 1
}

MST_WEBSITE_TARGETS="example.com|https://configured.example.com|200|5|true|true"
website_dedup_output="$(mst_website_targets_catalog)"
example_count="$(grep -c '^example.com|' <<< "${website_dedup_output}")"
shop_count="$(grep -c '^shop.example.net|' <<< "${website_dedup_output}")"
[[ "${example_count}" -eq 1 && "${shop_count}" -eq 1 ]] || {
    printf 'explicit website target should not be duplicated:\n%s\n' "${website_dedup_output}" >&2
    exit 1
}
[[ "${website_dedup_output}" == *"example.com|https://configured.example.com|200|5|true|true"* ]] || exit 1

MST_WORDPRESS_TARGETS="example.com|https://configured.example.com|${WP_ROOT}||wp|true"
wordpress_dedup_output="$(mst_wordpress_targets_catalog)"
example_wp_count="$(grep -c '^example.com|' <<< "${wordpress_dedup_output}")"
[[ "${example_wp_count}" -eq 1 ]] || {
    printf 'explicit WordPress target should not be duplicated:\n%s\n' "${wordpress_dedup_output}" >&2
    exit 1
}

printf 'test_discovery.sh passed.\n'
