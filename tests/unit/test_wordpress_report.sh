#!/usr/bin/env bash
# Validate aggregate WordPress MRRF1 generation and collector isolation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/wordpress-report"
PROC_DIR="${TMP_DIR}/proc"
mkdir -p "${PROC_DIR}/sys/kernel"

cat > "${PROC_DIR}/sys/kernel/hostname" <<'EOF'
wordpress-report
EOF

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/inspectors/wordpress.sh"

export MST_WORDPRESS_TARGETS="main|https://example.test|/var/www/main|/var/www/main/wp-config.php|wp|true;warn|https://warn.test|/var/www/warn|/var/www/warn/wp-config.php|wp|true;disabled|https://disabled.test|/var/www/disabled|/var/www/disabled/wp-config.php|wp|false"

mst_wordpress_collect_site() {
    local site_index="${1}"
    local name="${2}"
    local _site_url="${3}"
    local _document_root="${4}"
    local _wp_config_path="${5}"
    local _wp_cli_path="${6}"
    local enabled="${7}"
    local record_name="${8}"
    local details_name="${9}"
    local _errors_name="${10}"
    local rows_name="${11}"
    local -n record_ref="${record_name}"
    local -n details_ref="${details_name}"
    local -n rows_ref="${rows_name}"
    record_ref=()
    details_ref=()
    rows_ref=()
    mst_wordpress_record_init "${record_name}" "res_wordpress.${site_index}.$(mst_wordpress_result_suffix "${name}")" "${name}" "stub"
    if [[ "${enabled}" != "true" ]]; then
        record_ref[status]="unavailable"
        record_ref[severity]="unknown"
        record_ref[summary]="${name} disabled"
    elif [[ "${name}" == "warn" ]]; then
        record_ref[status]="warn"
        record_ref[severity]="warning"
        record_ref[summary]="${name} warning"
    else
        record_ref[status]="ok"
        record_ref[severity]="ok"
        record_ref[summary]="${name} ok"
    fi
    mst_wordpress_record_finalize "${record_name}" "$(mst_mrrf_now_epoch_ms)"
}

mst_wordpress_collect_report
python - <<'PY'
import json, os
report = json.loads(os.environ["MST_WORDPRESS_REPORT_JSON"])
assert report["document_type"] == "report"
assert report["command"] == "wordpress"
assert len(report["records"]) == 3
assert report["aggregate"]["record_count"] == 3
assert report["aggregate"]["module_summaries"][0]["module"] == "wordpress"
assert report["aggregate"]["overall_status"] == "unavailable"
PY

mst_wordpress_collect_site() {
    local _site_index="${1}"
    local name="${2}"
    local _site_url="${3}"
    local _document_root="${4}"
    local _wp_config_path="${5}"
    local _wp_cli_path="${6}"
    local _enabled="${7}"
    local record_name="${8}"
    local details_name="${9}"
    local _errors_name="${10}"
    local rows_name="${11}"

    if [[ "${name}" == "warn" ]]; then
        return 1
    fi

    local -n record_ref="${record_name}"
    local -n details_ref="${details_name}"
    local -n rows_ref="${rows_name}"
    record_ref=()
    details_ref=()
    rows_ref=()
    mst_wordpress_record_init "${record_name}" "placeholder" "${name}" "stub"
    record_ref[status]="ok"
    record_ref[severity]="ok"
    record_ref[summary]="${name} ok"
    mst_wordpress_record_finalize "${record_name}" "$(mst_mrrf_now_epoch_ms)"
}

mst_wordpress_collect_report
python - <<'PY'
import json, os
report = json.loads(os.environ["MST_WORDPRESS_REPORT_JSON"])
records = {record["target"]: record for record in report["records"]}
assert records["warn"]["status"] == "unknown"
assert any(error["code"] == "COLLECTOR_FAILURE" for error in records["warn"]["errors"])
PY

printf 'test_wordpress_report.sh passed.\n'
