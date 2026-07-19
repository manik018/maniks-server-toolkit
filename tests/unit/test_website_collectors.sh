#!/usr/bin/env bash
# Validate website collectors with local fixtures and mocked TLS paths.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/website-collectors"
PROC_DIR="${TMP_DIR}/proc"
mkdir -p "${PROC_DIR}/sys/kernel" "${TMP_DIR}"

cat > "${PROC_DIR}/sys/kernel/hostname" <<'EOF'
website-test
EOF

SERVER_PORT="$(python - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
)"

python "${ROOT_DIR}/tests/fixtures/website_mock_server.py" --port "${SERVER_PORT}" >"${TMP_DIR}/server.log" 2>&1 &
SERVER_PID=$!
cleanup() {
    kill "${SERVER_PID}" >/dev/null 2>&1 || true
    wait "${SERVER_PID}" 2>/dev/null || true
}
trap cleanup EXIT

for _ in 1 2 3 4 5 6 7 8 9 10; do
    if curl -sS "http://127.0.0.1:${SERVER_PORT}/ok" >/dev/null 2>&1; then
        break
    fi
    sleep 0.2
done

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/inspectors/website.sh"

export MST_WEBSITE_RESPONSE_WARN_MS="400"
export MST_WEBSITE_TLS_EXPIRY_WARN_DAYS="14"
export MST_WEBSITE_REDIRECT_WARN_COUNT="0"

declare -A http_record=()
declare -a http_details=() http_errors=() http_rows=()
mst_website_collect_target 1 "Main Site" "http://127.0.0.1:${SERVER_PORT}/ok" "200" "3" "true" "true" http_record http_details http_errors http_rows
[[ "${http_record[status]}" == "ok" ]] || exit 1
[[ "${http_record[summary]}" == *"returned 200"* ]] || exit 1

declare -A redirect_record=()
declare -a redirect_details=() redirect_errors=() redirect_rows=()
mst_website_collect_target 2 "Redirect Site" "http://127.0.0.1:${SERVER_PORT}/redirect" "200" "3" "true" "true" redirect_record redirect_details redirect_errors redirect_rows
[[ "${redirect_record[status]}" == "warn" ]] || exit 1

declare -A status_record=()
declare -a status_details=() status_errors=() status_rows=()
mst_website_collect_target 3 "Broken Status" "http://127.0.0.1:${SERVER_PORT}/status/500" "200" "3" "true" "true" status_record status_details status_errors status_rows
[[ "${status_record[status]}" == "critical" ]] || exit 1

mst_website_dns_lookup() {
    case "${1}" in
        tls-valid.local|tls-expired.local|tls-near.local|timeout.local|tcp-failure.local) printf '127.0.0.1 %s\n' "${1}" ;;
        *) return 1 ;;
    esac
}

mst_website_curl_probe() {
    case "${1}" in
        https://tls-valid.local/)
            printf 'url_effective=https://tls-valid.local/\nresponse_code=200\ntime_total=0.100\ntime_connect=0.020\nnum_redirects=0\ncontent_type=text/html\nsize_download=42\nremote_ip=127.0.0.1\nssl_verify_result=0\n'
            ;;
        https://tls-expired.local/)
            printf 'url_effective=https://tls-expired.local/\nresponse_code=200\ntime_total=0.100\ntime_connect=0.020\nnum_redirects=0\ncontent_type=text/html\nsize_download=42\nremote_ip=127.0.0.1\nssl_verify_result=0\n'
            ;;
        https://tls-near.local/)
            printf 'url_effective=https://tls-near.local/\nresponse_code=200\ntime_total=0.700\ntime_connect=0.020\nnum_redirects=0\ncontent_type=text/html\nsize_download=42\nremote_ip=127.0.0.1\nssl_verify_result=0\n'
            ;;
        http://timeout.local/)
            return 28
            ;;
        http://tcp-failure.local/)
            return 7
            ;;
        http://dns-failure.invalid/)
            return 6
            ;;
        *)
            return 1
            ;;
    esac
}

mst_website_tls_enddate() {
    case "${1}" in
        tls-valid.local) printf 'notAfter=Aug 30 12:00:00 2026 GMT\n' ;;
        tls-expired.local) printf 'notAfter=Jul 01 12:00:00 2026 GMT\n' ;;
        tls-near.local) printf 'notAfter=Jul 24 12:00:00 2026 GMT\n' ;;
        *) return 1 ;;
    esac
}

mst_command_exists() {
    case "${1}" in
        curl|openssl) return 0 ;;
        *) command -v "${1}" >/dev/null 2>&1 ;;
    esac
}

declare -A https_record=()
declare -a https_details=() https_errors=() https_rows=()
mst_website_collect_target 4 "HTTPS Valid" "https://tls-valid.local/" "200" "3" "true" "true" https_record https_details https_errors https_rows
[[ "${https_record[status]}" == "ok" ]] || exit 1

declare -A timeout_record=()
declare -a timeout_details=() timeout_errors=() timeout_rows=()
mst_website_collect_target 5 "Timeout Site" "http://timeout.local/" "200" "1" "true" "true" timeout_record timeout_details timeout_errors timeout_rows
[[ "${timeout_record[status]}" == "critical" ]] || exit 1
[[ "${timeout_errors[0]}" == timeout* ]] || exit 1

declare -A tcp_record=()
declare -a tcp_details=() tcp_errors=() tcp_rows=()
mst_website_collect_target 6 "TCP Failure" "http://tcp-failure.local/" "200" "1" "true" "true" tcp_record tcp_details tcp_errors tcp_rows
[[ "${tcp_record[status]}" == "critical" ]] || exit 1
[[ "${tcp_errors[0]}" == network* ]] || exit 1

declare -A expired_record=()
declare -a expired_details=() expired_errors=() expired_rows=()
mst_website_collect_target 7 "HTTPS Expired" "https://tls-expired.local/" "200" "3" "true" "true" expired_record expired_details expired_errors expired_rows
[[ "${expired_record[status]}" == "critical" ]] || exit 1

declare -A near_record=()
declare -a near_details=() near_errors=() near_rows=()
mst_website_collect_target 8 "HTTPS Near Expiry" "https://tls-near.local/" "200" "3" "true" "true" near_record near_details near_errors near_rows
[[ "${near_record[status]}" == "warn" ]] || exit 1

declare -A dns_record=()
declare -a dns_details=() dns_errors=() dns_rows=()
mst_website_collect_target 9 "DNS Failure" "http://dns-failure.invalid/" "200" "3" "true" "true" dns_record dns_details dns_errors dns_rows
[[ "${dns_record[status]}" == "critical" ]] || exit 1

printf 'test_website_collectors.sh passed.\n'
