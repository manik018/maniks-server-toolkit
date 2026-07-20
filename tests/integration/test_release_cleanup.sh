#!/usr/bin/env bash
# Validate release exclusion manifest keeps official artifacts clean.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="${MST_TEST_TMP_ROOT:-${ROOT_DIR}/.test-tmp}/release-cleanup"
SOURCE_DIR="${TMP_DIR}/source"
RELEASE_DIR_ONE="${TMP_DIR}/release-one"
RELEASE_DIR_TWO="${TMP_DIR}/release-two"
ARTIFACT_ONE="${RELEASE_DIR_ONE}/mst-release.tar.gz"
ARTIFACT_TWO="${RELEASE_DIR_TWO}/mst-release.tar.gz"
LIST_ONE="${TMP_DIR}/list-one.txt"
LIST_TWO="${TMP_DIR}/list-two.txt"
EXTRACT_DIR="${TMP_DIR}/extract"

rm -rf -- "${TMP_DIR}"
mkdir -p "${SOURCE_DIR}"

(cd "${ROOT_DIR}" && tar --exclude='./.test-tmp' --exclude='./dist' --exclude='./coverage' -cf - .) | (cd "${SOURCE_DIR}" && tar -xf -)

mkdir -p \
    "${SOURCE_DIR}/.test-tmp/cache" \
    "${SOURCE_DIR}/coverage" \
    "${SOURCE_DIR}/dist/staging" \
    "${SOURCE_DIR}/tests/__pycache__" \
    "${SOURCE_DIR}/docs"

printf 'test output\n' > "${SOURCE_DIR}/.test-tmp/cache/output.log"
printf 'coverage\n' > "${SOURCE_DIR}/coverage/index.html"
printf 'staging\n' > "${SOURCE_DIR}/dist/staging/old.txt"
printf 'tmp\n' > "${SOURCE_DIR}/runtime.tmp"
printf 'backup\n' > "${SOURCE_DIR}/README.md.bak"
printf 'orig\n' > "${SOURCE_DIR}/docs/release.md.orig"
printf 'rej\n' > "${SOURCE_DIR}/install.sh.rej"
printf 'swap\n' > "${SOURCE_DIR}/.notes.swp"
printf 'swap\n' > "${SOURCE_DIR}/.notes.swo"
printf 'editor\n' > "${SOURCE_DIR}/CHANGELOG.md~"
printf 'mac\n' > "${SOURCE_DIR}/.DS_Store"
printf 'thumb\n' > "${SOURCE_DIR}/Thumbs.db"
printf 'pyc\n' > "${SOURCE_DIR}/tests/__pycache__/fixture.pyc"
printf 'log\n' > "${SOURCE_DIR}/debug.log"

build_artifact() {
    local release_dir="${1:?release dir required}"
    mkdir -p "${release_dir}"
    (cd "${SOURCE_DIR}" && tar --sort=name --mtime='UTC 2026-07-18' --owner=0 --group=0 --numeric-owner --pax-option=delete=atime,delete=ctime --exclude-from=release.exclude -czf "${release_dir}/mst-release.tar.gz" .)
}

list_artifact() {
    local artifact_path="${1:?artifact required}"
    tar -tzf "${artifact_path}" | sed 's#^\./##' | sort
}

assert_present() {
    local relative_path="${1:?path required}"
    grep -Fxq "${relative_path}" "${LIST_ONE}" || {
        printf 'release artifact missing required file: %s\n' "${relative_path}" >&2
        exit 1
    }
}

assert_absent() {
    local pattern="${1:?pattern required}"
    if grep -Eq "${pattern}" "${LIST_ONE}"; then
        printf 'release artifact contains excluded entry matching: %s\n' "${pattern}" >&2
        exit 1
    fi
}

build_artifact "${RELEASE_DIR_ONE}"
build_artifact "${RELEASE_DIR_TWO}"
list_artifact "${ARTIFACT_ONE}" > "${LIST_ONE}"
list_artifact "${ARTIFACT_TWO}" > "${LIST_TWO}"

cmp -s "${ARTIFACT_ONE}" "${ARTIFACT_TWO}" || {
    printf 'release artifacts are not byte-for-byte reproducible.\n' >&2
    exit 1
}

cmp -s "${LIST_ONE}" "${LIST_TWO}" || {
    printf 'release artifact file list is not reproducible.\n' >&2
    exit 1
}

assert_present "mst"
assert_present "install.sh"
assert_present "uninstall.sh"
assert_present "README.md"
assert_present "LICENSE"
assert_present "CHANGELOG.md"
assert_present "docs/release.md"
assert_present "schemas/mrrf1.schema.json"
assert_present "scripts/mst-daily-report.sh"
assert_present "scripts/release-check.sh"
assert_present "tests/test_runner.sh"
assert_present "lib/runtime.sh"

assert_absent '(^|/)\.test-tmp(/|$)'
assert_absent '(^|/)coverage(/|$)'
assert_absent '(^|/)dist(/|$)'
assert_absent '\.tmp$'
assert_absent '\.bak$'
assert_absent '\.orig$'
assert_absent '\.rej$'
assert_absent '\.swp$'
assert_absent '\.swo$'
assert_absent '~$'
assert_absent '(^|/)\.DS_Store$'
assert_absent '(^|/)Thumbs\.db$'
assert_absent '(^|/)__pycache__(/|$)'
assert_absent '\.pyc$'
assert_absent '\.log$'
assert_absent 'mst-release.*\.tar\.gz$'

mkdir -p "${EXTRACT_DIR}"
tar -xzf "${ARTIFACT_ONE}" -C "${EXTRACT_DIR}"
if [[ "$(stat -c '%a' -- "${ROOT_DIR}/mst")" == "777" ]]; then
    printf 'release executable mode check skipped on filesystem without POSIX mode fidelity.\n'
else
    for executable_path in \
        "mst" \
        "install.sh" \
        "uninstall.sh" \
        "scripts/mst-daily-report.sh" \
        "scripts/release-check.sh" \
        "scripts/restore-executable-bits.sh" \
        "scripts/shellcheck.sh" \
        "tests/test_runner.sh"
    do
        mode="$(stat -c '%a' -- "${EXTRACT_DIR}/${executable_path}")"
        [[ "${mode}" == "755" ]] || {
            printf 'release executable has mode %s, expected 755: %s\n' "${mode}" "${executable_path}" >&2
            exit 1
        }
    done
fi

rm -rf -- "${TMP_DIR}"
[[ ! -e "${TMP_DIR}" ]] || exit 1

printf 'test_release_cleanup.sh passed.\n'
