#!/usr/bin/env bash
# MST foundation doctor command.

# Run the foundation self-review checks.
mst_command_doctor_run() {
    local exit_code="${MST_EXIT_OK}"
    local available_commands
    local available_inspectors
    local name requirement available version capability
    local label

    mst_header "$(mst_version_string)"
    mst_section "Foundation"
    mst_table_row "Config Schema" "${MST_CONFIG_SCHEMA_VERSION}"
    mst_table_row "Config File" "${MST_CONFIG_FILE}"
    mst_table_row "Output Mode" "${MST_OUTPUT_MODE}"
    mst_table_row "Log Level" "${MST_LOG_LEVEL}"
    mst_table_row "Timeout Seconds" "${MST_TIMEOUT_SECONDS}"

    mst_section "Paths"
    mst_table_row "Root" "${MST_ROOT}"
    mst_table_row "Command Dir" "${MST_COMMAND_DIR}"
    mst_table_row "Inspector Dir" "${MST_INSPECTOR_DIR}"
    mst_table_row "Log Dir" "${MST_LOG_DIR}"
    mst_table_row "State Dir" "${MST_STATE_DIR}"
    mst_table_row "Lock Dir" "${MST_LOCK_DIR}"

    mst_section "Discovery"
    available_commands="$(mst_discover_command_modules | sort | awk 'BEGIN { first=1 } { if (!first) printf ", "; printf "%s", $0; first=0 } END { printf "\n" }')"
    available_inspectors="$(mst_discover_inspector_modules | sort | awk 'BEGIN { first=1 } { if (!first) printf ", "; printf "%s", $0; first=0 } END { printf "\n" }')"
    mst_table_row "Command Modules" "${available_commands:-none}"
    mst_table_row "Inspector Modules" "${available_inspectors:-none}"

    mst_section "Dependencies"
    while IFS='|' read -r name requirement available version capability; do
        label="${name} (${capability})"
        if [[ "${available}" == "yes" ]]; then
            mst_table_row "${label}" "${requirement} / available / ${version}"
        else
            mst_table_row "${label}" "${requirement} / missing / ${version}"
            if [[ "${requirement}" == "required" ]]; then
                exit_code="${MST_EXIT_DEPENDENCY}"
            elif [[ "${exit_code}" -eq "${MST_EXIT_OK}" ]]; then
                exit_code="${MST_EXIT_PARTIAL}"
            fi
        fi
    done < <(mst_dependency_reports)

    mst_section "Safety"
    if mst_validate_schema_version "${MST_CONFIG_SCHEMA_VERSION}"; then
        mst_success_block "Config schema version is supported."
    else
        mst_error_block "Config schema version is unsupported."
        exit_code="${MST_EXIT_USAGE}"
    fi

    if [[ "${MST_LOG_WRITABLE:-0}" -eq 1 ]]; then
        mst_success_block "Logging sink is writable."
    else
        mst_warning_block "Logging sink is not writable in the current context."
        if [[ "${exit_code}" -eq "${MST_EXIT_OK}" ]]; then
            exit_code="${MST_EXIT_PARTIAL}"
        fi
    fi

    if mst_command_exists flock; then
        mst_success_block "flock is available for the locking framework."
    else
        mst_error_block "flock is missing."
        exit_code="${MST_EXIT_DEPENDENCY}"
    fi

    mst_log INFO doctor FOUNDATION_CHECK "Doctor command completed with exit code ${exit_code}"
    return "${exit_code}"
}
