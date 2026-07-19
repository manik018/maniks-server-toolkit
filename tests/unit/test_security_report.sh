#!/usr/bin/env bash
# Validate aggregate security MRRF1 generation and collector isolation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/security-report"
PROC_DIR="${TMP_DIR}/proc"

mkdir -p "${PROC_DIR}/sys/kernel"

cat > "${PROC_DIR}/sys/kernel/hostname" <<'EOF'
security-report
EOF

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/inspectors/security.sh"

export MST_SECURITY_PROC_DIR="${PROC_DIR}"

mst_security_collect_ssh() {
    local _check_id="${1}"
    local record_name="${2}"
    local details_name="${3}"
    local _errors_name="${4}"
    local rows_name="${5}"
    local -n record_ref="${record_name}"
    local -n details_ref="${details_name}"
    local -n rows_ref="${rows_name}"
    record_ref=()
    details_ref=()
    rows_ref=()
    mst_security_record_init "${record_name}" "res_security.ssh" "ssh" "SSH" "stub" "stub"
    record_ref[status]="ok"
    record_ref[severity]="ok"
    record_ref[summary]="ssh ok"
    mst_security_record_finalize "${record_name}" "$(mst_mrrf_now_epoch_ms)"
}

mst_security_collect_ufw() {
    local _check_id="${1}"
    local record_name="${2}"
    local details_name="${3}"
    local _errors_name="${4}"
    local rows_name="${5}"
    local -n record_ref="${record_name}"
    local -n details_ref="${details_name}"
    local -n rows_ref="${rows_name}"
    record_ref=()
    details_ref=()
    rows_ref=()
    mst_security_record_init "${record_name}" "res_security.ufw" "ufw" "UFW" "stub" "stub"
    record_ref[status]="warn"
    record_ref[severity]="warning"
    record_ref[summary]="ufw warning"
    mst_security_record_finalize "${record_name}" "$(mst_mrrf_now_epoch_ms)"
}

mst_security_collect_fail2ban() {
    local _check_id="${1}"
    local record_name="${2}"
    local details_name="${3}"
    local _errors_name="${4}"
    local rows_name="${5}"
    local -n record_ref="${record_name}"
    local -n details_ref="${details_name}"
    local -n rows_ref="${rows_name}"
    record_ref=()
    details_ref=()
    rows_ref=()
    mst_security_record_init "${record_name}" "res_security.fail2ban" "fail2ban" "Fail2Ban" "stub" "stub"
    record_ref[status]="ok"
    record_ref[severity]="ok"
    record_ref[summary]="fail2ban ok"
    mst_security_record_finalize "${record_name}" "$(mst_mrrf_now_epoch_ms)"
}

mst_security_collect_unattended_upgrades() {
    local _check_id="${1}"
    local record_name="${2}"
    local details_name="${3}"
    local _errors_name="${4}"
    local rows_name="${5}"
    local -n record_ref="${record_name}"
    local -n details_ref="${details_name}"
    local -n rows_ref="${rows_name}"
    record_ref=()
    details_ref=()
    rows_ref=()
    mst_security_record_init "${record_name}" "res_security.unattended_upgrades" "unattended_upgrades" "Automatic Security Updates" "stub" "stub"
    record_ref[status]="ok"
    record_ref[severity]="ok"
    record_ref[summary]="upgrades ok"
    mst_security_record_finalize "${record_name}" "$(mst_mrrf_now_epoch_ms)"
}

mst_security_collect_time_sync() {
    local _check_id="${1}"
    local record_name="${2}"
    local details_name="${3}"
    local _errors_name="${4}"
    local rows_name="${5}"
    local -n record_ref="${record_name}"
    local -n details_ref="${details_name}"
    local -n rows_ref="${rows_name}"
    record_ref=()
    details_ref=()
    rows_ref=()
    mst_security_record_init "${record_name}" "res_security.time_sync" "time_sync" "Time Synchronization" "stub" "stub"
    record_ref[status]="ok"
    record_ref[severity]="ok"
    record_ref[summary]="time ok"
    mst_security_record_finalize "${record_name}" "$(mst_mrrf_now_epoch_ms)"
}

mst_security_collect_report
python - <<'PY'
import json, os
report = json.loads(os.environ["MST_SECURITY_REPORT_JSON"])
assert report["document_type"] == "report"
assert report["command"] == "security"
assert len(report["records"]) == 5
assert report["aggregate"]["record_count"] == 5
assert report["aggregate"]["module_summaries"][0]["module"] == "security"
assert report["aggregate"]["overall_status"] == "warn"
PY

mst_security_collect_ufw() {
    return 1
}

mst_security_collect_report
python - <<'PY'
import json, os
report = json.loads(os.environ["MST_SECURITY_REPORT_JSON"])
records = {record["result_id"]: record for record in report["records"]}
assert records["res_security.ufw"]["status"] == "unknown"
assert any(error["code"] == "COLLECTOR_FAILURE" for error in records["res_security.ufw"]["errors"])
PY

printf 'test_security_report.sh passed.\n'
