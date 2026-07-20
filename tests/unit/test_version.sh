#!/usr/bin/env bash
# Validate the release version reported by the CLI.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

output="$("${ROOT_DIR}/mst" version)"
[[ "${output}" == "Manik's Server Toolkit 1.0.5" ]] || {
    printf 'unexpected version output: %s\n' "${output}" >&2
    exit 1
}

printf 'test_version.sh passed.\n'
