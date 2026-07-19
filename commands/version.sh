#!/usr/bin/env bash
# MST version command.

# Print the current toolkit version.
mst_command_version_run() {
    printf '%s\n' "$(mst_version_string)"
}
