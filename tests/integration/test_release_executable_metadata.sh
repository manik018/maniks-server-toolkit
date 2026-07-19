#!/usr/bin/env bash
# Validate release executable metadata restoration.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/release-executable-metadata"
ARTIFACT_DIR="${TMP_DIR}/artifact"
BIN_DIR="${TMP_DIR}/bin"
MODE_DB="${TMP_DIR}/modes.db"

required_executables=(
    "mst"
    "install.sh"
    "uninstall.sh"
    "scripts/release-check.sh"
    "scripts/restore-executable-bits.sh"
    "scripts/shellcheck.sh"
    "tests/test_runner.sh"
)

non_executables=(
    "lib/alert.sh"
    "README.md"
    "docs/release.md"
)

mode_of() {
    local path="${1:?path required}"
    awk -F'|' -v target="${path}" '$1 == target { mode=$2 } END { print mode }' "${MODE_DB}"
}

assert_executable() {
    local path="${1:?path required}"
    local mode owner_digit group_digit other_digit
    mode="$(mode_of "${path}")"
    owner_digit="${mode: -3:1}"
    group_digit="${mode: -2:1}"
    other_digit="${mode: -1}"
    (( (10#${owner_digit} & 1) != 0 && (10#${group_digit} & 1) != 0 && (10#${other_digit} & 1) != 0 )) || {
        printf 'expected executable: %s\n' "${path}" >&2
        exit 1
    }
}

assert_mode() {
    local path="${1:?path required}"
    local expected="${2:?mode required}"
    local actual
    actual="$(mode_of "${path}")"
    [[ "${actual}" == "${expected}" ]] || {
        printf 'expected %s mode %s, got %s\n' "${path}" "${expected}" "${actual}" >&2
        exit 1
    }
}

copy_artifact_file() {
    local relative_path="${1:?path required}"
    mkdir -p "${ARTIFACT_DIR}/$(dirname -- "${relative_path}")"
    cp -- "${ROOT_DIR}/${relative_path}" "${ARTIFACT_DIR}/${relative_path}"
}

record_mode() {
    local path="${1:?path required}"
    local mode="${2:?mode required}"
    awk -F'|' -v target="${path}" '$1 != target { print }' "${MODE_DB}" > "${MODE_DB}.tmp" 2>/dev/null || true
    printf '%s|%s\n' "${path}" "${mode}" >> "${MODE_DB}.tmp"
    mv -f -- "${MODE_DB}.tmp" "${MODE_DB}"
}

rm -rf -- "${TMP_DIR}"
mkdir -p "${ARTIFACT_DIR}" "${BIN_DIR}"
: > "${MODE_DB}"

cat > "${BIN_DIR}/chmod" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mode="${1:?mode required}"
shift
[[ "${1:-}" == "--" ]] && shift

for path in "$@"; do
    case "${mode}" in
        [0-7][0-7][0-7])
            next="${mode}"
            ;;
        [0-7][0-7][0-7][0-7])
            next="${mode#0}"
            ;;
        *)
            printf 'unsupported chmod mode in release metadata test: %s\n' "${mode}" >&2
            exit 1
            ;;
    esac
    awk -F'|' -v target="${path}" '$1 != target { print }' "${MST_RELEASE_MODE_DB}" > "${MST_RELEASE_MODE_DB}.tmp" 2>/dev/null || true
    printf '%s|%s\n' "${path}" "${next}" >> "${MST_RELEASE_MODE_DB}.tmp"
    mv -f -- "${MST_RELEASE_MODE_DB}.tmp" "${MST_RELEASE_MODE_DB}"
done
EOF
chmod 0755 "${BIN_DIR}/chmod"

for relative_path in "${required_executables[@]}" "${non_executables[@]}"; do
    copy_artifact_file "${relative_path}"
done

record_mode "${ARTIFACT_DIR}/lib/alert.sh" "644"
record_mode "${ARTIFACT_DIR}/README.md" "644"
record_mode "${ARTIFACT_DIR}/docs/release.md" "600"

for initial_mode in 644 666 600 777; do
    for relative_path in "${required_executables[@]}"; do
        record_mode "${ARTIFACT_DIR}/${relative_path}" "${initial_mode}"
        assert_mode "${ARTIFACT_DIR}/${relative_path}" "${initial_mode}"
    done

    MST_RELEASE_MODE_DB="${MODE_DB}" PATH="${BIN_DIR}:${PATH}" bash "${ARTIFACT_DIR}/scripts/restore-executable-bits.sh" >/dev/null

    for relative_path in "${required_executables[@]}"; do
        assert_executable "${ARTIFACT_DIR}/${relative_path}"
        assert_mode "${ARTIFACT_DIR}/${relative_path}" "755"
    done
done

assert_mode "${ARTIFACT_DIR}/lib/alert.sh" "644"
assert_mode "${ARTIFACT_DIR}/README.md" "644"
assert_mode "${ARTIFACT_DIR}/docs/release.md" "600"

snapshot_before="$(sort "${MODE_DB}")"
MST_RELEASE_MODE_DB="${MODE_DB}" PATH="${BIN_DIR}:${PATH}" bash "${ARTIFACT_DIR}/scripts/restore-executable-bits.sh" >/dev/null
snapshot_after="$(sort "${MODE_DB}")"
[[ "${snapshot_before}" == "${snapshot_after}" ]] || {
    printf 'restore-executable-bits.sh is not idempotent.\n' >&2
    exit 1
}

rm -rf -- "${TMP_DIR}"
[[ ! -e "${TMP_DIR}" ]] || exit 1

printf 'test_release_executable_metadata.sh passed.\n'
