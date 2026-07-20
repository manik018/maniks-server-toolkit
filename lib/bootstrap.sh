#!/usr/bin/env bash
# MST foundation bootstrap and command dispatch.

if [[ -n "${MST_BOOTSTRAP_LOADED:-}" ]]; then
    return
fi
readonly MST_BOOTSTRAP_LOADED=1

# Load the core runtime in deterministic order.
mst_bootstrap() {
    local root="${1:?root required}"
    local canonical_root

    canonical_root="$(mst_bootstrap_validate_root "${root}")" || {
        printf 'Invalid runtime root.\n' >&2
        exit 1
    }

    if [[ -n "${MST_ROOT:-}" ]] && [[ "${MST_ROOT}" != "${canonical_root}" ]]; then
        printf 'Runtime root mismatch.\n' >&2
        exit 1
    fi

    if [[ -z "${MST_ROOT:-}" ]]; then
        readonly MST_ROOT="${canonical_root}"
        export MST_ROOT
    fi

    readonly MST_LIB_DIR="${canonical_root}/lib"
    readonly MST_COMMAND_DIR="${canonical_root}/commands"
    readonly MST_INSPECTOR_DIR="${canonical_root}/inspectors"
    readonly MST_RENDERER_DIR="${canonical_root}/renderers"
    readonly MST_DELIVERY_DIR="${canonical_root}/delivery"
    export MST_LIB_DIR MST_COMMAND_DIR MST_INSPECTOR_DIR MST_RENDERER_DIR MST_DELIVERY_DIR

    # shellcheck source=lib/runtime.sh
    source "${MST_LIB_DIR}/runtime.sh"
    # shellcheck source=lib/errors.sh
    source "${MST_LIB_DIR}/errors.sh"
    # shellcheck source=lib/validate.sh
    source "${MST_LIB_DIR}/validate.sh"
    # shellcheck source=lib/filesystem.sh
    source "${MST_LIB_DIR}/filesystem.sh"
    # shellcheck source=lib/state.sh
    source "${MST_LIB_DIR}/state.sh"
    # shellcheck source=lib/output.sh
    source "${MST_LIB_DIR}/output.sh"
    # shellcheck source=lib/logging.sh
    source "${MST_LIB_DIR}/logging.sh"
    # shellcheck source=lib/exec.sh
    source "${MST_LIB_DIR}/exec.sh"
    # shellcheck source=lib/discover.sh
    source "${MST_LIB_DIR}/discover.sh"
    # shellcheck source=lib/mrrf.sh
    source "${MST_LIB_DIR}/mrrf.sh"
    # shellcheck source=lib/config.sh
    source "${MST_LIB_DIR}/config.sh"
}

# Validate and canonicalize the runtime root before any module is loaded.
mst_bootstrap_validate_root() {
    local root="${1:?root required}"
    local canonical_root

    canonical_root="$(readlink -f -- "${root}")" || return 1
    [[ -d "${canonical_root}" ]] || return 1
    [[ -f "${canonical_root}/mst" ]] || return 1
    [[ -f "${canonical_root}/lib/bootstrap.sh" ]] || return 1
    [[ -f "${canonical_root}/lib/runtime.sh" ]] || return 1
    [[ -f "${canonical_root}/lib/errors.sh" ]] || return 1
    [[ -f "${canonical_root}/commands/help.sh" ]] || return 1
    printf '%s' "${canonical_root}"
}

# Return the known public command registry.
mst_command_registry() {
    cat <<'EOF'
help|help|implemented
version|version|implemented
doctor|doctor|implemented
health|health|implemented
services|services|implemented
security|security|implemented
website|website|implemented
wordpress|wordpress|implemented
backup|backup|implemented
performance|not-implemented|stub
system|not-implemented|stub
report|report|implemented
telegram|telegram|implemented
alert|alert|implemented
alert-check|not-implemented|stub
update|not-implemented|stub
config|config|stub
EOF
}

# List the known public commands in display order.
mst_list_public_commands() {
    mst_command_registry | awk -F'|' '{ print $1 }'
}

# Resolve a public command id to a command module filename.
mst_resolve_command_module() {
    local command_id="${1:?command id required}"
    mst_command_registry | awk -F'|' -v command_id="${command_id}" '$1 == command_id { print $2 }'
}

# Resolve a public command id to its implementation status.
mst_command_status() {
    local command_id="${1:?command id required}"
    mst_command_registry | awk -F'|' -v command_id="${command_id}" '$1 == command_id { print $3 }'
}

# Return success if the command exists in the public registry.
mst_is_known_command() {
    local command_id="${1:?command id required}"
    [[ -n "$(mst_resolve_command_module "${command_id}")" ]]
}

# Discover command modules that exist on disk.
mst_discover_command_modules() {
    local path
    for path in "${MST_COMMAND_DIR}"/*.sh; do
        [[ -e "${path}" ]] || continue
        basename "${path}" .sh
    done
}

# Discover inspector modules on disk for future phases.
mst_discover_inspector_modules() {
    local path
    for path in "${MST_INSPECTOR_DIR}"/*.sh; do
        [[ -e "${path}" ]] || continue
        basename "${path}" .sh
    done
}

# Load one command module by filename.
mst_load_command_module() {
    local module_name="${1:?module name required}"
    local module_path="${MST_COMMAND_DIR}/${module_name}.sh"
    if [[ ! -f "${module_path}" ]]; then
        mst_die "${MST_EXIT_INTERNAL}" "Command module not found: ${module_name}"
    fi

    # shellcheck disable=SC1090
    source "${module_path}"
}

# Parse global options and resolve the requested command id.
mst_parse_cli() {
    MST_GLOBAL_OUTPUT_MODE=""
    MST_GLOBAL_VERBOSE=0
    MST_GLOBAL_QUIET=0
    MST_GLOBAL_NO_COLOR=0
    MST_GLOBAL_TIMEOUT=""
    MST_GLOBAL_CONFIG_FILE=""
    MST_COMMAND_ID="help"
    MST_COMMAND_ARGS=()

    local argv=("$@")
    local index=0
    local command_seen=0

    while (( index < ${#argv[@]} )); do
        case "${argv[index]}" in
            --config)
                index=$((index + 1))
                (( index < ${#argv[@]} )) || mst_die "${MST_EXIT_USAGE}" "Missing value for --config"
                MST_GLOBAL_CONFIG_FILE="${argv[index]}"
                ;;
            --output)
                index=$((index + 1))
                (( index < ${#argv[@]} )) || mst_die "${MST_EXIT_USAGE}" "Missing value for --output"
                MST_GLOBAL_OUTPUT_MODE="${argv[index]}"
                ;;
            --timeout)
                index=$((index + 1))
                (( index < ${#argv[@]} )) || mst_die "${MST_EXIT_USAGE}" "Missing value for --timeout"
                MST_GLOBAL_TIMEOUT="${argv[index]}"
                ;;
            --verbose)
                MST_GLOBAL_VERBOSE=1
                ;;
            --quiet)
                MST_GLOBAL_QUIET=1
                ;;
            --no-color)
                MST_GLOBAL_NO_COLOR=1
                ;;
            --help|-h)
                if (( command_seen == 0 )); then
                    MST_COMMAND_ID="help"
                    MST_COMMAND_ARGS=()
                    return 0
                fi
                MST_COMMAND_ARGS+=("${argv[index]}")
                ;;
            --version|-V)
                if (( command_seen == 0 )); then
                    MST_COMMAND_ID="version"
                    MST_COMMAND_ARGS=()
                    return 0
                fi
                MST_COMMAND_ARGS+=("${argv[index]}")
                ;;
            *)
                if (( command_seen == 0 )); then
                    command_seen=1
                    MST_COMMAND_ID="${argv[index]}"
                else
                    MST_COMMAND_ARGS+=("${argv[index]}")
                fi
                ;;
        esac
        index=$((index + 1))
    done

    case "${MST_COMMAND_ID}" in
        "" ) MST_COMMAND_ID="help" ;;
        config)
            if [[ "${MST_COMMAND_ARGS[*]:-}" == "show" ]]; then
                MST_COMMAND_ARGS=("show")
            elif [[ "${#MST_COMMAND_ARGS[@]}" -eq 0 ]]; then
                MST_COMMAND_ARGS=("show")
            else
                mst_die "${MST_EXIT_USAGE}" "Unsupported config subcommand"
            fi
            ;;
    esac

    if ! mst_is_known_command "${MST_COMMAND_ID}"; then
        mst_error_block "Unknown command: ${MST_COMMAND_ID}"
        MST_COMMAND_ID="help"
        return "${MST_EXIT_USAGE}"
    fi
    return 0
}

# Dispatch the requested public command.
mst_dispatch() {
    local parse_exit=0
    mst_parse_cli "$@" || parse_exit=$?
    mst_runtime_init
    mst_apply_global_cli_options
    mst_output_init
    if [[ "${MST_COMMAND_ID}" == "doctor" ]] || [[ "${MST_COMMAND_ID}" == "health" ]] || [[ "${MST_COMMAND_ID}" == "services" ]] || [[ "${MST_COMMAND_ID}" == "security" ]] || [[ "${MST_COMMAND_ID}" == "website" ]] || [[ "${MST_COMMAND_ID}" == "wordpress" ]] || [[ "${MST_COMMAND_ID}" == "backup" ]] || [[ "${MST_COMMAND_ID}" == "telegram" ]] || [[ "${MST_COMMAND_ID}" == "alert" ]]; then
        mst_config_load
    fi
    mst_logging_init

    local module_name
    module_name="$(mst_resolve_command_module "${MST_COMMAND_ID}")"
    mst_load_command_module "${module_name}"

    local function_name="mst_command_${module_name//-/_}_run"
    if ! declare -F "${function_name}" >/dev/null 2>&1; then
        mst_die "${MST_EXIT_INTERNAL}" "Command entrypoint missing: ${function_name}"
    fi

    "${function_name}" "${MST_COMMAND_ARGS[@]}"
    local command_exit=$?

    if [[ "${parse_exit}" -ne 0 ]] && [[ "${command_exit}" -eq 0 ]]; then
        return "${parse_exit}"
    fi
    return "${command_exit}"
}
