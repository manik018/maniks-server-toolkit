#!/usr/bin/env bash
# Validate default uninstall path handling in dry-run mode.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# shellcheck source=../../uninstall.sh
source "${ROOT_DIR}/uninstall.sh"

require_root() {
    return 0
}

output="$(main --dry-run)"
[[ "${output}" == *"MST foundation uninstallation complete."* ]] || exit 1

printf 'test_uninstaller.sh passed.\n'
