#!/usr/bin/env bash
# Validate release-check.sh resolves project resources independent of caller cwd.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/release-check-working-directory"
PROJECT_DIR="${TMP_DIR}/project"
SIBLING_DIR="${TMP_DIR}/sibling"
NESTED_DIR="${PROJECT_DIR}/nested/deep"

rm -rf -- "${TMP_DIR}"
mkdir -p "${PROJECT_DIR}/scripts" "${PROJECT_DIR}/tests" "${PROJECT_DIR}/schemas" "${SIBLING_DIR}" "${NESTED_DIR}"

cp -- "${ROOT_DIR}/scripts/release-check.sh" "${PROJECT_DIR}/scripts/release-check.sh"
chmod 0755 "${PROJECT_DIR}/scripts/release-check.sh"

cat > "${PROJECT_DIR}/schemas/mrrf1.schema.json" <<'EOF'
{"type":"object"}
EOF

cat > "${PROJECT_DIR}/scripts/shellcheck.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${MST_RELEASE_CHECK_FAIL_SHELLCHECK:-false}" == "true" ]]; then
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

run_and_expect_success() {
    local work_dir="${1:?work dir required}"
    local command_text="${2:?command required}"
    local output

    output="$(cd "${work_dir}" && eval "${command_text}")"
    [[ "${output}" == *"schema-json-ok"* ]] || exit 1
    [[ "${output}" == *"shellcheck-stub-ok"* ]] || exit 1
    [[ "${output}" == *"test-runner-stub-ok"* ]] || exit 1
}

run_and_expect_success "${PROJECT_DIR}" "scripts/release-check.sh"
run_and_expect_success "${SIBLING_DIR}" "'${PROJECT_DIR}/scripts/release-check.sh'"
run_and_expect_success "${NESTED_DIR}" "../../scripts/release-check.sh"
run_and_expect_success "${TMP_DIR}" "'${PROJECT_DIR}/scripts/release-check.sh'"
run_and_expect_success "${TMP_DIR}" "project/scripts/release-check.sh"

mv -- "${PROJECT_DIR}/schemas/mrrf1.schema.json" "${PROJECT_DIR}/schemas/mrrf1.schema.json.good"
printf '{invalid-json\n' > "${PROJECT_DIR}/schemas/mrrf1.schema.json"
set +e
schema_failure_output="$(cd "${SIBLING_DIR}" && "${PROJECT_DIR}/scripts/release-check.sh" 2>&1)"
schema_failure_status=$?
set -e
[[ "${schema_failure_status}" -ne 0 ]] || exit 1
[[ "${schema_failure_output}" != *"shellcheck-stub-ok"* ]] || exit 1
mv -- "${PROJECT_DIR}/schemas/mrrf1.schema.json.good" "${PROJECT_DIR}/schemas/mrrf1.schema.json"

set +e
shellcheck_failure_output="$(cd "${NESTED_DIR}" && MST_RELEASE_CHECK_FAIL_SHELLCHECK=true ../../scripts/release-check.sh 2>&1)"
shellcheck_failure_status=$?
set -e
[[ "${shellcheck_failure_status}" -ne 0 ]] || exit 1
[[ "${shellcheck_failure_output}" == *"schema-json-ok"* ]] || exit 1
[[ "${shellcheck_failure_output}" == *"shellcheck-stub-failed"* ]] || exit 1
[[ "${shellcheck_failure_output}" != *"test-runner-stub-ok"* ]] || exit 1

rm -rf -- "${TMP_DIR}"
[[ ! -e "${TMP_DIR}" ]] || exit 1

printf 'test_release_check_working_directory.sh passed.\n'
