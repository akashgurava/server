#!/bin/bash
# Stop Unbound DNS Server

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library functions
source "$SCRIPT_DIR/lib.sh"

echo ""
echo "$(printf '=%.0s' {1..80})"
echo "Stopping Unbound DNS Server"
echo "$(printf '=%.0s' {1..80})"
echo ""

# Check if Unbound is running
if check_unbound_running; then
    echo "Stopping Unbound..."
    stop_unbound
    
    # Verify it stopped
    if ! check_unbound_running; then
        echo "✓ Unbound stopped successfully"
    else
        echo "⚠️  Unbound may still be running"
    fi
else
    echo "Unbound is not running"
fi

echo ""
echo "$(printf '=%.0s' {1..80})"
echo "Done"
echo "$(printf '=%.0s' {1..80})"
echo ""
