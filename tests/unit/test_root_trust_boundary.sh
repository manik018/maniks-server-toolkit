#!/usr/bin/env bash
# Validate that MST_ROOT from the environment is ignored.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${ROOT_DIR}/.test-tmp/root-boundary"
EVIL_DIR="${TMP_DIR}/evil"
MARKER_FILE="${TMP_DIR}/poisoned"

mkdir -p "${EVIL_DIR}/lib"
cat > "${EVIL_DIR}/lib/bootstrap.sh" <<EOF
#!/usr/bin/env bash
printf 'poisoned\n' > "${MARKER_FILE}"
EOF

output="$(MST_ROOT="${EVIL_DIR}" "${ROOT_DIR}/mst" version)"
[[ "${output}" == *"1.0.6"* ]] || exit 1
[[ ! -e "${MARKER_FILE}" ]] || exit 1

printf 'test_root_trust_boundary.sh passed.\n'
