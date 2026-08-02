#!/usr/bin/env bash
# Validate the security events scaffold collector.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
source "${ROOT_DIR}/inspectors/security_events.sh"

declare -A placeholder_record=()
declare -a placeholder_details=() placeholder_errors=()
mst_security_events_collect placeholder_record placeholder_details placeholder_errors

[[ "${placeholder_record[check]}" == "module_status" ]] || exit 1
[[ "${placeholder_record[status]}" == "ok" ]] || exit 1
[[ "${placeholder_record[summary]}" == "Security events module is enabled with no checks implemented yet." ]] || exit 1
[[ "${#placeholder_details[@]}" == "0" ]] || exit 1
[[ "${#placeholder_errors[@]}" == "0" ]] || exit 1

printf 'test_security_events_collectors.sh passed.\n'
