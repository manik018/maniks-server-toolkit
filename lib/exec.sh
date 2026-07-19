#!/usr/bin/env bash
# MST command execution and dependency detection helpers.

# Return success if the command exists.
mst_command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Run a command with a timeout and capture stdout to the caller.
mst_exec_capture_stdout() {
    local timeout_seconds="${1:?timeout required}"
    shift || true
    timeout "${timeout_seconds}" "$@"
}

# Return the dependency catalog in a stable format.
mst_dependency_catalog() {
    cat <<'EOF'
bash|required|shell
awk|required|text
sed|required|text
grep|required|text
cut|required|text
sort|required|text
uniq|required|text
date|required|time
stat|required|filesystem
find|required|filesystem
chgrp|required|filesystem
timeout|required|process
flock|required|locking
df|optional|runtime
free|optional|runtime
ps|optional|runtime
ss|optional|runtime
systemctl|optional|runtime
journalctl|optional|runtime
hostname|optional|runtime
uname|optional|runtime
curl|optional|delivery
shellcheck|optional|developer
EOF
}

# Return the preferred version flag for a dependency.
mst_dependency_version_flag() {
    case "${1:?dependency required}" in
        awk) printf '%s' '-W version' ;;
        *) printf '%s' '--version' ;;
    esac
}

# Return the first-line version string for a dependency or UNKNOWN.
mst_dependency_version() {
    local name="${1:?dependency required}"
    local version_flag
    local output

    mst_command_exists "${name}" || {
        printf 'MISSING'
        return 0
    }

    version_flag="$(mst_dependency_version_flag "${name}")"
    # shellcheck disable=SC2086
    output="$(${name} ${version_flag} 2>&1 | awk 'NR==1 { print; exit }' || true)"
    if [[ -n "${output}" ]]; then
        printf '%s' "${output}"
    else
        printf 'UNKNOWN'
    fi
}

# Return availability, version, and capability for a dependency.
mst_dependency_report_line() {
    local name="${1:?dependency required}"
    local requirement="${2:?requirement required}"
    local capability="${3:?capability required}"
    local available="no"

    if mst_command_exists "${name}"; then
        available="yes"
    fi

    printf '%s|%s|%s|%s|%s\n' \
        "${name}" \
        "${requirement}" \
        "${available}" \
        "$(mst_dependency_version "${name}")" \
        "${capability}"
}

# List dependency reports for doctor and installers.
mst_dependency_reports() {
    local entry name requirement capability
    while IFS='|' read -r name requirement capability; do
        [[ -n "${name}" ]] || continue
        mst_dependency_report_line "${name}" "${requirement}" "${capability}"
    done < <(mst_dependency_catalog)
}
