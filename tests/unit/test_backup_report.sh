#!/usr/bin/env bash
# Validate aggregate backup MRRF1 generation and collector isolation.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/backup-report"
PROC_DIR="${TMP_DIR}/proc"
mkdir -p "${PROC_DIR}/sys/kernel"

cat > "${PROC_DIR}/sys/kernel/hostname" <<'EOF'
backup-report
EOF

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/inspectors/backup.sh"

export MST_BACKUP_TARGETS="localdir|local_directory|/backups|daily|24|10|true;remote|rclone_remote|remote:bucket|daily|24|10|true;disabled|local_file|/backups/disabled.tar.gz|daily|24|10|false"

mst_backup_collect_target() {
    local target_index="${1}"
    local name="${2}"
    local _target_type="${3}"
    local _location="${4}"
    local _expected_frequency="${5}"
    local _maximum_age_hours="${6}"
    local _minimum_size_mb="${7}"
    local enabled="${8}"
    local record_name="${9}"
    local details_name="${10}"
    local _errors_name="${11}"
    local rows_name="${12}"
    local -n record_ref="${record_name}"
    local -n details_ref="${details_name}"
    local -n rows_ref="${rows_name}"
    record_ref=()
    details_ref=()
    rows_ref=()
    mst_backup_record_init "${record_name}" "res_backup.${target_index}.$(mst_backup_result_suffix "${name}")" "${name}" "stub"
    if [[ "${enabled}" != "true" ]]; then
        record_ref[status]="unavailable"
        record_ref[severity]="unknown"
        record_ref[summary]="${name} disabled"
    elif [[ "${name}" == "remote" ]]; then
        record_ref[status]="warn"
        record_ref[severity]="warning"
        record_ref[summary]="${name} warning"
    else
        record_ref[status]="ok"
        record_ref[severity]="ok"
        record_ref[summary]="${name} ok"
    fi
    mst_backup_record_finalize "${record_name}" "$(mst_mrrf_now_epoch_ms)"
}

mst_backup_collect_report
python - <<'PY'
import json, os
report = json.loads(os.environ["MST_BACKUP_REPORT_JSON"])
assert report["document_type"] == "report"
assert report["command"] == "backup"
assert len(report["records"]) == 3
assert report["aggregate"]["record_count"] == 3
assert report["aggregate"]["module_summaries"][0]["module"] == "backup"
assert report["aggregate"]["overall_status"] == "unavailable"
PY

mst_backup_collect_target() {
    local _target_index="${1}"
    local name="${2}"
    local _target_type="${3}"
    local _location="${4}"
    local _expected_frequency="${5}"
    local _maximum_age_hours="${6}"
    local _minimum_size_mb="${7}"
    local _enabled="${8}"
    local record_name="${9}"
    local details_name="${10}"
    local _errors_name="${11}"
    local rows_name="${12}"

    if [[ "${name}" == "remote" ]]; then
        return 1
    fi

    local -n record_ref="${record_name}"
    local -n details_ref="${details_name}"
    local -n rows_ref="${rows_name}"
    record_ref=()
    details_ref=()
    rows_ref=()
    mst_backup_record_init "${record_name}" "placeholder" "${name}" "stub"
    record_ref[status]="ok"
    record_ref[severity]="ok"
    record_ref[summary]="${name} ok"
    mst_backup_record_finalize "${record_name}" "$(mst_mrrf_now_epoch_ms)"
}

mst_backup_collect_report
python - <<'PY'
import json, os
report = json.loads(os.environ["MST_BACKUP_REPORT_JSON"])
records = {record["target"]: record for record in report["records"]}
assert records["remote"]["status"] == "unknown"
assert any(error["code"] == "COLLECTOR_FAILURE" for error in records["remote"]["errors"])
PY

printf 'test_backup_report.sh passed.\n'
