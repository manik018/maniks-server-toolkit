#!/usr/bin/env bash
# Validate dependency reporting.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=lib/bootstrap.sh
source "${ROOT_DIR}/lib/bootstrap.sh"
mst_bootstrap "${ROOT_DIR}"

if ! mst_dependency_reports | awk -F'|' '$1 == "bash" && $2 == "required" { found=1 } END { exit(found ? 0 : 1) }'; then
    printf 'bash dependency missing from report.\n' >&2
    exit 1
fi

printf 'test_dependencies.sh passed.\n'
