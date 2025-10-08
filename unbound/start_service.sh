#!/bin/bash
# Start Unbound DNS Server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLIMA_WAS_RUNNING=false

# Source library functions
source "$SCRIPT_DIR/lib.sh"

# --- Root Privilege Check ---
# Ensure the script is run as root, as many operations require sudo.
if ! is_running_as_root; then
    echo "Error: This script must be run with root privileges." >&2
    echo "Please try again using 'sudo ./start_service.sh'" >&2
    exit 1
fi

# Check if Unbound binary exists
if ! is_unbound_installed; then
    echo "Error: Unbound is not installed at $UNBOUND_BIN"
    echo "Run ./setup.sh first"
    exit 1
fi

# Check if config exists
if ! is_unbound_config_exists; then
    echo "Error: Unbound configuration not found at $UNBOUND_CONFIG"
    echo "Run ./setup.sh first"
    exit 1
fi

RUN_STATUS=0
SERVICE_STATUS=0
GENERIC_RESPONSE_STATUS=0
ROUTING_RESPONSE_STATUS=0

STATUS=""

# Color codes for status output
GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

if is_unbound_running; then
    RUN_STATUS=1
    STATUS="RUN_STATUS: ✅."
else
    RUN_STATUS=0
    STATUS="RUN_STATUS: ❌."
fi

 if is_unbound_brew_service_running; then
    SERVICE_STATUS=1
    STATUS+=" SERVICE_STATUS: ✅."
else
    SERVICE_STATUS=0
    STATUS+=" SERVICE_STATUS: ❌."
fi

if is_unbound_responding_generic; then
    GENERIC_RESPONSE_STATUS=1
    STATUS+=" GENERIC_RESPONSE_STATUS: ✅."
else
    GENERIC_RESPONSE_STATUS=0
    STATUS+=" GENERIC_RESPONSE_STATUS: ❌."
fi


if is_unbound_responding; then
    ROUTING_RESPONSE_STATUS=1
    STATUS+=" ROUTING_RESPONSE_STATUS: ✅."
else
    ROUTING_RESPONSE_STATUS=0
    STATUS+=" ROUTING_RESPONSE_STATUS: ❌."
fi

# Compute summary and pick color
SUM=$((RUN_STATUS + SERVICE_STATUS + GENERIC_RESPONSE_STATUS + ROUTING_RESPONSE_STATUS))
if [[ $SUM -eq 4 ]]; then
    COLOR="$GREEN"
elif [[ $SUM -eq 0 ]]; then
    COLOR="$RED"
else
    COLOR="$BLUE"
fi

echo -e "${COLOR}INITIAL_STATUS: $STATUS${NC}"

# If not all OK, try to ensure service is running, then recompute and print final status
if [[ $SUM -ne 4 ]]; then
    ensure_unbound_running

    # Recompute statuses
    STATUS=""
    if is_unbound_running; then
        RUN_STATUS=1
        STATUS="RUN_STATUS: ✅."
    else
        RUN_STATUS=0
        STATUS="RUN_STATUS: ❌."
    fi

    if is_unbound_brew_service_running; then
        SERVICE_STATUS=1
        STATUS+=" SERVICE_STATUS: ✅."
    else
        SERVICE_STATUS=0
        STATUS+=" SERVICE_STATUS: ❌."
    fi

    if is_unbound_responding_generic; then
        GENERIC_RESPONSE_STATUS=1
        STATUS+=" GENERIC_RESPONSE_STATUS: ✅."
    else
        GENERIC_RESPONSE_STATUS=0
        STATUS+=" GENERIC_RESPONSE_STATUS: ❌."
    fi

    if is_unbound_responding; then
        ROUTING_RESPONSE_STATUS=1
        STATUS+=" ROUTING_RESPONSE_STATUS: ✅."
    else
        ROUTING_RESPONSE_STATUS=0
        STATUS+=" ROUTING_RESPONSE_STATUS: ❌."
    fi

    SUM=$((RUN_STATUS + SERVICE_STATUS + GENERIC_RESPONSE_STATUS + ROUTING_RESPONSE_STATUS))
    if [[ $SUM -eq 4 ]]; then
        COLOR="$GREEN"
    elif [[ $SUM -eq 0 ]]; then
        COLOR="$RED"
    else
        COLOR="$BLUE"
    fi

    echo -e "${COLOR}STATUS: $STATUS${NC}"
fi