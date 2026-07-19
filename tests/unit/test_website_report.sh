#!/usr/bin/env bash
# Validate aggregate website MRRF1 generation and collector isolation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/website-report"
PROC_DIR="${TMP_DIR}/proc"
mkdir -p "${PROC_DIR}/sys/kernel"

cat > "${PROC_DIR}/sys/kernel/hostname" <<'EOF'
website-report
EOF

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/inspectors/website.sh"

export MST_WEBSITE_TARGETS="main|http://127.0.0.1/|200|3|true|true;api|https://api.local/|200|3|true|true;disabled|https://disabled.local/|200|3|true|false"

mst_website_collect_target() {
    local website_index="${1}"
    local name="${2}"
    local _url="${3}"
    local _expected_status="${4}"
    local _timeout_seconds="${5}"
    local _follow_redirects="${6}"
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
    mst_website_record_init "${record_name}" "res_website.${website_index}.$(mst_website_result_suffix "${name}")" "${name}" "stub"
    if [[ "${enabled}" != "true" ]]; then
        record_ref[status]="unavailable"
        record_ref[severity]="unknown"
        record_ref[summary]="${name} disabled"
    elif [[ "${name}" == "api" ]]; then
        record_ref[status]="warn"
        record_ref[severity]="warning"
        record_ref[summary]="${name} warning"
    else
        record_ref[status]="ok"
        record_ref[severity]="ok"
        record_ref[summary]="${name} ok"
    fi
    mst_website_record_finalize "${record_name}" "$(mst_mrrf_now_epoch_ms)"
}

mst_website_collect_report
python - <<'PY'
import json, os
report = json.loads(os.environ["MST_WEBSITE_REPORT_JSON"])
assert report["document_type"] == "report"
assert report["command"] == "website"
assert len(report["records"]) == 3
assert report["aggregate"]["record_count"] == 3
assert report["aggregate"]["module_summaries"][0]["module"] == "website"
assert report["aggregate"]["overall_status"] == "unavailable"
PY

mst_website_collect_target() {
    local website_index="${1}"
    local name="${2}"
    local _url="${3}"
    local _expected_status="${4}"
    local _timeout_seconds="${5}"
    local _follow_redirects="${6}"
    local _enabled="${7}"
    local record_name="${8}"
    local details_name="${9}"
    local _errors_name="${10}"
    local rows_name="${11}"

    if [[ "${name}" == "api" ]]; then
        return 1
    fi

    local -n record_ref="${record_name}"
    local -n details_ref="${details_name}"
    local -n rows_ref="${rows_name}"
    record_ref=()
    details_ref=()
    rows_ref=()
    mst_website_record_init "${record_name}" "res_website.${website_index}.$(mst_website_result_suffix "${name}")" "${name}" "stub"
    record_ref[status]="ok"
    record_ref[severity]="ok"
    record_ref[summary]="${name} ok"
    mst_website_record_finalize "${record_name}" "$(mst_mrrf_now_epoch_ms)"
}

mst_website_collect_report
python - <<'PY'
import json, os
report = json.loads(os.environ["MST_WEBSITE_REPORT_JSON"])
records = {record["target"]: record for record in report["records"]}
assert records["api"]["status"] == "unknown"
assert any(error["code"] == "COLLECTOR_FAILURE" for error in records["api"]["errors"])
PY

printf 'test_website_report.sh passed.\n'
