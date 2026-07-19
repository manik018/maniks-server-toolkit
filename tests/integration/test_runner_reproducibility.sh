#!/usr/bin/env bash
# Validate test runner reproducibility and cleanup behavior with a tiny fake suite.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/runner-reproducibility"
PASS_UNIT_DIR="${TMP_DIR}/pass/unit"
PASS_INTEGRATION_DIR="${TMP_DIR}/pass/integration"
FAIL_UNIT_DIR="${TMP_DIR}/fail/unit"
FAIL_INTEGRATION_DIR="${TMP_DIR}/fail/integration"

rm -rf -- "${TMP_DIR}"
mkdir -p "${PASS_UNIT_DIR}" "${PASS_INTEGRATION_DIR}" "${FAIL_UNIT_DIR}" "${FAIL_INTEGRATION_DIR}"

cat > "${PASS_UNIT_DIR}/test_01_create_state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ -n "${MST_TEST_TMP_ROOT:-}" ]] || exit 1
[[ ! -e "${MST_TEST_TMP_ROOT}/state/alerts.state" ]] || exit 1
[[ ! -e "${MST_TEST_TMP_ROOT}/logs/mst.log" ]] || exit 1
[[ ! -e "${MST_TEST_TMP_ROOT}/configs/config.conf" ]] || exit 1

mkdir -p "${MST_TEST_TMP_ROOT}/state" "${MST_TEST_TMP_ROOT}/logs" "${MST_TEST_TMP_ROOT}/configs"
printf 'alert-state\n' > "${MST_TEST_TMP_ROOT}/state/alerts.state"
printf 'log-line\n' > "${MST_TEST_TMP_ROOT}/logs/mst.log"
printf 'MST_CONFIG_SCHEMA_VERSION="1"\n' > "${MST_TEST_TMP_ROOT}/configs/config.conf"

printf 'fake_create_state passed.\n'
EOF

cat > "${PASS_INTEGRATION_DIR}/test_02_cleanup_visible.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ -n "${MST_TEST_TMP_ROOT:-}" ]] || exit 1
[[ ! -e "${MST_TEST_TMP_ROOT}/state/alerts.state" ]] || exit 1
[[ ! -e "${MST_TEST_TMP_ROOT}/logs/mst.log" ]] || exit 1
[[ ! -e "${MST_TEST_TMP_ROOT}/configs/config.conf" ]] || exit 1
[[ ! -e "${MST_TEST_TMP_ROOT}/failure/alerts.state" ]] || exit 1

printf 'fake_cleanup_visible passed.\n'
EOF

cat > "${FAIL_UNIT_DIR}/test_01_failure_leaves_state.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p "${MST_TEST_TMP_ROOT}/failure"
printf 'failure-state\n' > "${MST_TEST_TMP_ROOT}/failure/alerts.state"
printf 'intentional failure\n' >&2
exit 42
EOF

run_fake_suite() {
    local tmp_root="${1:?tmp root required}"
    local unit_dir="${2:?unit dir required}"
    local integration_dir="${3:?integration dir required}"

    MST_TEST_TMP_ROOT="${tmp_root}" \
    MST_TEST_UNIT_DIR="${unit_dir}" \
    MST_TEST_INTEGRATION_DIR="${integration_dir}" \
        bash "${ROOT_DIR}/tests/test_runner.sh"
}

output_one="$(run_fake_suite "${TMP_DIR}/nested-pass-tmp" "${PASS_UNIT_DIR}" "${PASS_INTEGRATION_DIR}")"
[[ ! -e "${TMP_DIR}/nested-pass-tmp" ]] || exit 1

output_two="$(run_fake_suite "${TMP_DIR}/nested-pass-tmp" "${PASS_UNIT_DIR}" "${PASS_INTEGRATION_DIR}")"
[[ ! -e "${TMP_DIR}/nested-pass-tmp" ]] || exit 1

output_three="$(run_fake_suite "${TMP_DIR}/nested-pass-tmp" "${PASS_UNIT_DIR}" "${PASS_INTEGRATION_DIR}")"
[[ ! -e "${TMP_DIR}/nested-pass-tmp" ]] || exit 1

[[ "${output_one}" == "${output_two}" ]] || exit 1
[[ "${output_two}" == "${output_three}" ]] || exit 1
[[ "${output_one}" == *"fake_create_state passed."* ]] || exit 1
[[ "${output_one}" == *"fake_cleanup_visible passed."* ]] || exit 1
[[ "${output_one}" == *"Foundation test suite completed."* ]] || exit 1

set +e
failure_output="$(run_fake_suite "${TMP_DIR}/nested-fail-tmp" "${FAIL_UNIT_DIR}" "${FAIL_INTEGRATION_DIR}" 2>&1)"
failure_status=$?
set -e

[[ "${failure_status}" -ne 0 ]] || exit 1
[[ "${failure_output}" == *"intentional failure"* ]] || exit 1
[[ "${failure_output}" != *"Foundation test suite completed."* ]] || exit 1
[[ ! -e "${TMP_DIR}/nested-fail-tmp" ]] || exit 1

recovery_output="$(run_fake_suite "${TMP_DIR}/nested-fail-tmp" "${PASS_UNIT_DIR}" "${PASS_INTEGRATION_DIR}")"
[[ "${recovery_output}" == "${output_one}" ]] || exit 1
[[ ! -e "${TMP_DIR}/nested-fail-tmp" ]] || exit 1

rm -rf -- "${TMP_DIR}"
[[ ! -e "${TMP_DIR}" ]] || exit 1

printf 'test_runner_reproducibility.sh passed.\n'
