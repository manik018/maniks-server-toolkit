#!/usr/bin/env bash
# Validate centralized error code mapping.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"

[[ "$(mst_exit_code_for_category warning)" -eq 7 ]] || exit 1
[[ "$(mst_exit_code_for_category dependency)" -eq 3 ]] || exit 1
[[ "$(mst_exit_code_for_category permission)" -eq 4 ]] || exit 1

printf 'test_errors.sh passed.\n'
