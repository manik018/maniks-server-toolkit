#!/usr/bin/env bash
# Validate backup collectors with local fixtures and mocked rclone metadata.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/backup-collectors"
PROC_DIR="${TMP_DIR}/proc"
LOCAL_DIR="${TMP_DIR}/local-dir"
LOCAL_FILE_DIR="${TMP_DIR}/local-file"
mkdir -p "${PROC_DIR}/sys/kernel" "${LOCAL_DIR}" "${LOCAL_FILE_DIR}"

cat > "${PROC_DIR}/sys/kernel/hostname" <<'EOF'
backup-test
EOF

printf 'recent-backup' > "${LOCAL_DIR}/recent.tar.gz"
printf 'file-backup' > "${LOCAL_FILE_DIR}/backup.sql.gz"
printf 'small' > "${LOCAL_DIR}/small.tar.gz"
touch -d '2026-07-17 10:00:00 UTC' "${LOCAL_DIR}/recent.tar.gz"
touch -d '2026-07-17 09:00:00 UTC' "${LOCAL_FILE_DIR}/backup.sql.gz"
touch -d '2026-07-15 09:00:00 UTC' "${LOCAL_DIR}/small.tar.gz"

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/inspectors/backup.sh"

mst_backup_detect_hostname() {
    printf 'backup-test'
}

mst_backup_now_epoch() {
    printf '1784289600'
}

declare -A dir_record=()
declare -a dir_details=() dir_errors=() dir_rows=()
mst_backup_collect_target 1 "Directory Target" "local_directory" "${LOCAL_DIR}" "daily" "72" "0" "true" dir_record dir_details dir_errors dir_rows
[[ "${dir_record[status]}" == "ok" ]] || exit 1

declare -A file_record=()
declare -a file_details=() file_errors=() file_rows=()
mst_backup_collect_target 2 "File Target" "local_file" "${LOCAL_FILE_DIR}/backup.sql.gz" "daily" "72" "0" "true" file_record file_details file_errors file_rows
[[ "${file_record[status]}" == "ok" ]] || exit 1

declare -A missing_record=()
declare -a missing_details=() missing_errors=() missing_rows=()
mst_backup_collect_target 3 "Missing Target" "local_file" "${TMP_DIR}/missing.tar.gz" "daily" "72" "0" "true" missing_record missing_details missing_errors missing_rows
[[ "${missing_record[status]}" == "critical" ]] || exit 1

declare -A stale_record=()
declare -a stale_details=() stale_errors=() stale_rows=()
mst_backup_collect_target 4 "Stale Target" "local_file" "${LOCAL_DIR}/small.tar.gz" "daily" "1" "0" "true" stale_record stale_details stale_errors stale_rows
[[ "${stale_record[status]}" == "warn" ]] || exit 1

declare -A small_record=()
declare -a small_details=() small_errors=() small_rows=()
mst_backup_collect_target 5 "Small Target" "local_file" "${LOCAL_DIR}/small.tar.gz" "daily" "100" "10" "true" small_record small_details small_errors small_rows
[[ "${small_record[status]}" == "warn" ]] || exit 1

mst_backup_target_readable() {
    case "${1}" in
        *unreadable.tar.gz) return 1 ;;
        *) [[ -r "${1:-}" ]] ;;
    esac
}
printf 'secret' > "${TMP_DIR}/unreadable.tar.gz"
declare -A unreadable_record=()
declare -a unreadable_details=() unreadable_errors=() unreadable_rows=()
mst_backup_collect_target 6 "Unreadable Target" "local_file" "${TMP_DIR}/unreadable.tar.gz" "daily" "72" "0" "true" unreadable_record unreadable_details unreadable_errors unreadable_rows
[[ "${unreadable_record[status]}" == "critical" ]] || exit 1

mst_command_exists() {
    case "${1}" in
        rclone) return 0 ;;
        *) command -v "${1}" >/dev/null 2>&1 ;;
    esac
}

mst_backup_rclone_remote_configured() {
    [[ "${1}" == "remote" ]]
}

mst_backup_rclone_lsjson() {
    case "${1}" in
        remote:bucket)
            printf '[{"Path":"backup-2026-07-17.tar.gz","Name":"backup-2026-07-17.tar.gz","Size":10485760,"ModTime":"2026-07-17T08:00:00Z"}]\n'
            ;;
        remote:down)
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

declare -A rclone_record=()
declare -a rclone_details=() rclone_errors=() rclone_rows=()
mst_backup_collect_target 7 "Remote Target" "rclone_remote" "remote:bucket" "daily" "72" "1" "true" rclone_record rclone_details rclone_errors rclone_rows
[[ "${rclone_record[status]}" == "ok" ]] || exit 1

declare -A rclone_down_record=()
declare -a rclone_down_details=() rclone_down_errors=() rclone_down_rows=()
mst_backup_collect_target 8 "Remote Down" "rclone_remote" "remote:down" "daily" "72" "1" "true" rclone_down_record rclone_down_details rclone_down_errors rclone_down_rows
[[ "${rclone_down_record[status]}" == "critical" ]] || exit 1

printf 'test_backup_collectors.sh passed.\n'
