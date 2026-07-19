#!/usr/bin/env bash
# Validate installer dry-run behavior.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if ! grep -q -- '--dry-run' "${ROOT_DIR}/install.sh"; then
    printf 'installer dry-run support missing.\n' >&2
    exit 1
fi

if grep -q 'cp -R' "${ROOT_DIR}/install.sh"; then
    printf 'installer must not use recursive cp for runtime tree permissions.\n' >&2
    exit 1
fi

if ! grep -q 'verify_install_permissions' "${ROOT_DIR}/install.sh"; then
    printf 'installer post-install permission verification missing.\n' >&2
    exit 1
fi

if ! grep -q 'Ubuntu 24.04' "${ROOT_DIR}/docs/architecture-design-document.md"; then
    printf 'architecture document no longer references Ubuntu 24.04.\n' >&2
    exit 1
fi

printf 'test_installer.sh passed.\n'
