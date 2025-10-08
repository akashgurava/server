#!/bin/bash
# Unbound Library Functions
#
# Core functions for managing the Unbound DNS resolver.
# Intended for use by wrapper scripts like start_service.sh, stop_service.sh, etc.
# Assumes execution on macOS with Unbound installed via Homebrew.
#
# Dependencies: unbound, dig, lsof

# --- Configuration ---
# This allows the calling script or user to specify different paths without modifying this library.
UNBOUND_SBIN_DIR=${UNBOUND_SBCONFIG_DIR:-"/opt/homebrew/sbin"}
UNBOUND_ETC_DIR=${UNBOUND_ETC_DIR:-"/opt/homebrew/etc/unbound"}

UNBOUND_BIN="${UNBOUND_SBIN_DIR}/unbound"
UNBOUND_CHECKCONF_BIN="${UNBOUND_SBIN_DIR}/unbound-checkconf"
UNBOUND_CONFIG="${UNBOUND_ETC_DIR}/unbound.conf"

# --- Process & Service Checks ---

# Check if the script is running with root privileges.
# Returns: 0 if running as root, 1 if not.
is_running_as_root() {
    [[ $EUID -eq 0 ]]
}

# Check if the Unbound process is running by exact name.
# Returns: 0 if running, 1 if not.
is_unbound_running() {
    pgrep -x "unbound" > /dev/null
}

# Check if the Homebrew service for Unbound is running.
# Returns: 0 if running, 1 if not.
is_unbound_brew_service_running() {
    sudo brew services list | grep -E "^unbound\s+(started|running)" > /dev/null 2>&1
}

# Check if Unbound is actively responding to a general internet domain.
# Returns: 0 if responding, 1 if not.
is_unbound_responding_generic() {
    # Using a short timeout and single try for a quick health check.
    dig @127.0.0.1 +time=2 +tries=1 google.com > /dev/null 2>&1
}

# Check if Unbound is actively responding to a routing test domain.
# Returns: 0 if responding, 1 if not.
is_unbound_responding() {
    # Using a short timeout and single try for a quick health check.
    dig @127.0.0.1 +time=2 +tries=1 firefox.225274x.xyz > /dev/null 2>&1
}

# Check if the Unbound binary exists and is executable.
# Returns: 0 if it exists, 1 if not.
is_unbound_installed() {
    [[ -x "$UNBOUND_BIN" ]]
}

# Check if the Unbound config file exists and is readable.
# Returns: 0 if it exists, 1 if not.
is_unbound_config_exists() {
    [[ -r "$UNBOUND_CONFIG" ]]
}

# --- Service Management ---

# Stop the Unbound Homebrew service with retries and error reporting.
# Echos error message and returns 1 on failure. Returns 0 on success.
ensure_unbound_brew_service_not_running() {
    local output
    output=$(sudo brew services stop unbound 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "BREW_SERVICE_STOP_CMD_FAILED_ERR: ${output}"
        return 1
    fi

    for _ in {1..5}; do
        if ! is_unbound_brew_service_running; then
            return 0 # Success
        fi
        sleep 2
    done

    echo "BREW_SERVICE_NOT_STOPPED_ERR: Unbound Homebrew service did not stop after 5 retries."
    return 1
}

# Stop the Unbound process by first stopping the service, then killing the process.
# Echos error message and returns 1 on failure. Returns 0 on success.
ensure_unbound_not_running() {
    # If the process is not running, there's nothing to stop.
    if ! is_unbound_running; then
        return 0
    fi

    local stop_output
    stop_output=$(ensure_unbound_brew_service_not_running)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "$stop_output"
        return 1
    fi

    # If brew service stopped but process is lingering, try to kill it.
    if is_unbound_running; then
        for _ in {1..5}; do
            sudo pkill "unbound" >/dev/null 2>&1 || true
            sleep 2
            if ! is_unbound_running; then
                return 0 # Success
            fi
        done
        
        # If after 10 seconds of pkill it's still running
        echo "UNBOUND_PROCESS_NOT_KILLED"
        return 1
    fi
    
    return 0
}

# Start (or restart) Unbound via Homebrew service and ensure it is running.
# Returns: 0 on success, 1 on failure.
ensure_unbound_running() {
    # Restart service to ensure desired state
    local restart_output
    restart_output=$(sudo brew services restart unbound 2>&1)
    local exit_code=$?

    if [[ $exit_code -ne 0 ]]; then
        echo "BREW_SERVICE_RESTART_CMD_FAILED_ERR: ${restart_output}"
        return 1
    fi

    # Wait for brew service to report running
    for _ in {1..5}; do
        if is_unbound_brew_service_running; then
            break
        fi
        sleep 2
    done

    if ! is_unbound_brew_service_running; then
        echo "BREW_SERVICE_NOT_STARTED_ERR: Unbound Homebrew service did not start after 5 retries."
        return 1
    fi

    # Wait for process to be up
    for _ in {1..5}; do
        if is_unbound_running; then
            break
        fi
        sleep 2
    done

    if ! is_unbound_running; then
        echo "UNBOUND_PROCESS_NOT_STARTED_ERR: Unbound process did not start after service restart."
        return 1
    fi

    # One-shot DNS response checks (no retries)
    if ! is_unbound_responding_generic; then
        echo "UNBOUND_GENERIC_DNS_CHECK_FAILED_ERR: Unbound not responding to generic DNS queries (google.com)."
        return 1
    fi

    if ! is_unbound_responding; then
        echo "UNBOUND_ROUTING_DNS_CHECK_FAILED_ERR: Unbound not responding to routing test domain (firefox.225274x.xyz)."
        return 1
    fi

    return 0
}

# Validate the Unbound configuration file for errors.
# On success, returns 0.
# On failure, echos the error message from the validation command and returns 1.
validate_unbound_config() {
    local output
    output=$(sudo "$UNBOUND_CHECKCONF_BIN" "$UNBOUND_CONFIG" 2>&1)
    local exit_code=$?
    # Return the validator's output via stdout so callers can capture it,
    # and propagate the exit code to indicate success/failure.
    echo "$output"
    return $exit_code
}

# # --- Utility Functions ---

# # Check what process is using the DNS port (53).
# # Returns: Process info as a string or an empty string if port is free.
# check_port_53() {
#     sudo lsof -i :53 -sTCP:LISTEN 2>/dev/null
# }

# # Forcefully kill a process by its PID.
# # Args: $1 = PID
# # Returns: 0 on success.
# kill_pid() {
#     local pid=$1
#     if [[ -n "$pid" ]]; then
#         sudo kill -9 "$pid" >/dev/null 2>&1 || true
#         sleep 1
#     fi
# }

# # --- Getters & Prerequisite Checks ---

# # Get the configured path to the Unbound binary.
# get_unbound_bin() {
#     echo "$UNBOUND_BIN"
# }

# # Get the configured path to the Unbound config file.
# get_unbound_config() {
#     echo "$UNBOUND_CONFIG"
# }

