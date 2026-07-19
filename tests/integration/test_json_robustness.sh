#!/usr/bin/env bash
# Validate release-check JSON robustness for expected bad inputs.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/json-robustness"
PROJECT_DIR="${TMP_DIR}/project"
SCHEMA_FILE="${PROJECT_DIR}/schemas/mrrf1.schema.json"

rm -rf -- "${TMP_DIR}"
mkdir -p "${PROJECT_DIR}/scripts" "${PROJECT_DIR}/tests" "${PROJECT_DIR}/schemas"

cp -- "${ROOT_DIR}/scripts/release-check.sh" "${PROJECT_DIR}/scripts/release-check.sh"
chmod 0755 "${PROJECT_DIR}/scripts/release-check.sh"

cat > "${PROJECT_DIR}/scripts/shellcheck.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${MST_JSON_TEST_FAIL_SHELLCHECK:-false}" == "true" ]]; then
    printf 'shellcheck-stub-failed\n' >&2
    exit 42
fi
printf 'shellcheck-stub-ok\n'
EOF
chmod 0755 "${PROJECT_DIR}/scripts/shellcheck.sh"

cat > "${PROJECT_DIR}/tests/test_runner.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'test-runner-stub-ok\n'
EOF
chmod 0755 "${PROJECT_DIR}/tests/test_runner.sh"

run_release_check() {
    (cd "${TMP_DIR}" && "${PROJECT_DIR}/scripts/release-check.sh")
}

expect_success() {
    local output
    output="$(run_release_check)"
    [[ "${output}" == *"schema-json-ok"* ]] || exit 1
    [[ "${output}" == *"shellcheck-stub-ok"* ]] || exit 1
    [[ "${output}" == *"test-runner-stub-ok"* ]] || exit 1
}

expect_json_failure() {
    local expected_text="${1:?message required}"
    local output status

    set +e
    output="$(run_release_check 2>&1)"
    status=$?
    set -e

    [[ "${status}" -ne 0 ]] || {
        printf 'release-check should have rejected JSON: %s\n' "${expected_text}" >&2
        exit 1
    }
    [[ "${output}" == *"json-error:"* && "${output}" == *"schemas"* && "${output}" == *"mrrf1.schema.json:"* ]] || {
        printf 'JSON error did not identify file: %s\n' "${output}" >&2
        exit 1
    }
    [[ "${output}" == *"${expected_text}"* ]] || {
        printf 'JSON error did not contain %s: %s\n' "${expected_text}" "${output}" >&2
        exit 1
    }
    [[ "${output}" != *"Traceback"* ]] || exit 1
    [[ "${output}" != *"shellcheck-stub-ok"* ]] || exit 1
    [[ "${output}" != *"test-runner-stub-ok"* ]] || exit 1
}

printf '{"type":"object"}\n' > "${SCHEMA_FILE}"
expect_success

: > "${SCHEMA_FILE}"
expect_json_failure "empty JSON document"

printf '{"type": object}\n' > "${SCHEMA_FILE}"
expect_json_failure "malformed JSON"

printf '{"type":"object"\n' > "${SCHEMA_FILE}"
expect_json_failure "malformed JSON"

printf '[]\n' > "${SCHEMA_FILE}"
expect_json_failure "expected top-level JSON object"

printf 'true\n' > "${SCHEMA_FILE}"
expect_json_failure "expected top-level JSON object"

printf '{"type":"object"}\n' > "${SCHEMA_FILE}"
set +e
failure_output="$(cd "${TMP_DIR}" && MST_JSON_TEST_FAIL_SHELLCHECK=true "${PROJECT_DIR}/scripts/release-check.sh" 2>&1)"
failure_status=$?
set -e
[[ "${failure_status}" -ne 0 ]] || exit 1
[[ "${failure_output}" == *"schema-json-ok"* ]] || exit 1
[[ "${failure_output}" == *"shellcheck-stub-failed"* ]] || exit 1
[[ "${failure_output}" != *"test-runner-stub-ok"* ]] || exit 1

rm -rf -- "${TMP_DIR}"
[[ ! -e "${TMP_DIR}" ]] || exit 1

printf 'test_json_robustness.sh passed.\n'
