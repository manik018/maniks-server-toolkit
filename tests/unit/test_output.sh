#!/usr/bin/env bash
# Validate output helper functions execute successfully.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"
mst_runtime_init

mst_header "Header" >/dev/null
mst_section "Section" >/dev/null
mst_table_row "Key" "Value" >/dev/null
mst_success_block "ok" >/dev/null
mst_warning_block "warn" >/dev/null

printf 'test_output.sh passed.\n'
