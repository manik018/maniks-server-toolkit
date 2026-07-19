#!/usr/bin/env bash
# MST help command.

# Render the CLI help output.
mst_command_help_run() {
    mst_header "$(mst_version_string)"
    mst_section "Usage"
    printf '  mst [global-options] <command> [arguments]\n'

    mst_section "Working Commands"
    mst_table_row "mst" "Show this help"
    mst_table_row "mst help" "Show command help"
    mst_table_row "mst version" "Show toolkit version"
    mst_table_row "mst doctor" "Run foundation self-checks"
    mst_table_row "mst health" "Collect local operating-system health"
    mst_table_row "mst services" "Collect local systemd service health"
    mst_table_row "mst security" "Collect local security posture"
    mst_table_row "mst website" "Collect website availability and TLS health"
    mst_table_row "mst wordpress" "Collect WordPress site health"
    mst_table_row "mst backup" "Collect backup freshness and metadata health"
    mst_table_row "mst report" "Render unified terminal report from MRRF1 data"
    mst_table_row "mst telegram" "Deliver pre-rendered text to Telegram"
    mst_table_row "mst alert" "Evaluate MRRF1 reports into alert decisions"

    mst_section "Foundation-Only Stubs"
    mst_table_row "mst performance" "NOT IMPLEMENTED"
    mst_table_row "mst system" "NOT IMPLEMENTED"
    mst_table_row "mst alert-check" "NOT IMPLEMENTED"
    mst_table_row "mst update" "NOT IMPLEMENTED"
    mst_table_row "mst config show" "NOT IMPLEMENTED"

    mst_section "Global Options"
    mst_table_row "--config FILE" "Use a specific configuration file"
    mst_table_row "--output MODE" "Set output mode: text or json"
    mst_table_row "--timeout SEC" "Override the default timeout"
    mst_table_row "--verbose" "Enable verbose runtime messages"
    mst_table_row "--quiet" "Suppress non-essential info output"
    mst_table_row "--no-color" "Disable ANSI color rendering"
}
