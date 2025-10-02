#!/bin/bash
# Start Unbound DNS Server
# Handles port 53 conflicts with Colima/Lima

set -e

UNBOUND_BIN="/opt/homebrew/sbin/unbound"
UNBOUND_CONFIG="/opt/homebrew/etc/unbound/unbound.conf"
COLIMA_WAS_RUNNING=false

echo "========================================="
echo "Starting Unbound DNS Server"
echo "========================================="
echo ""

# Check if Unbound binary exists
if [ ! -f "$UNBOUND_BIN" ]; then
    echo "Error: Unbound is not installed"
    echo "Run ./setup.sh first"
    exit 1
fi

# Check if config exists
if [ ! -f "$UNBOUND_CONFIG" ]; then
    echo "Error: Unbound configuration not found"
    echo "Run ./setup.sh first"
    exit 1
fi

# Step 1: Check for Colima/Lima
echo "Step 1: Checking for Colima/Lima..."
if colima status &>/dev/null && colima status | grep -q "Running"; then
    echo "⚠️  Colima is currently running"
    echo ""
    read -p "Stop Colima? [Y/n]: " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        COLIMA_WAS_RUNNING=true
        echo "Stopping Colima..."
        colima stop 2>/dev/null || lima stop 2>/dev/null || true
        echo "✓ Colima stopped"
        sleep 2
    else
        echo "Cannot start Unbound while Colima is running (port 53 conflict)"
        exit 1
    fi
else
    echo "✓ Colima is not running"
fi
echo ""

# Step 2: Check if Unbound is already running
echo "Step 2: Checking if Unbound is already running..."
if pgrep -x unbound > /dev/null; then
    echo "⚠️  Unbound is already running"
    echo ""
    read -p "Restart Unbound? [Y/n]: " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        echo "Stopping Unbound..."
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -f "$SCRIPT_DIR/stop_service.sh" ]; then
            "$SCRIPT_DIR/stop_service.sh"
        else
            sudo pkill unbound || true
        fi
        sleep 2
        echo "✓ Unbound stopped"
    else
        echo "Unbound is already running"
        exit 0
    fi
else
    echo "✓ Unbound is not running"
fi
echo ""

# Step 3: Final check - anything else using port 53
echo "Step 3: Checking port 53..."
PORT_CHECK=$(sudo lsof -i :53 -sTCP:LISTEN 2>/dev/null || true)

if [ -n "$PORT_CHECK" ]; then
    echo "⚠️  Port 53 is still in use by another process:"
    echo ""
    echo "$PORT_CHECK"
    echo ""
    
    # Extract process info
    PROCESS_INFO=$(echo "$PORT_CHECK" | grep -v COMMAND | head -1)
    PROCESS_NAME=$(echo "$PROCESS_INFO" | awk '{print $1}')
    PROCESS_PID=$(echo "$PROCESS_INFO" | awk '{print $2}')
    
    echo "Process: $PROCESS_NAME (PID: $PROCESS_PID)"
    echo ""
    read -p "Terminate process $PROCESS_PID? [y/N]: " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Terminating process $PROCESS_PID..."
        sudo kill "$PROCESS_PID"
        sleep 2
        echo "✓ Process terminated"
    else
        echo "Cannot start Unbound while port 53 is in use"
        exit 1
    fi
else
    echo "✓ Port 53 is available"
fi
echo ""

# Step 4: Validate configuration
echo "Step 4: Validating configuration..."
if sudo "$UNBOUND_BIN"-checkconf "$UNBOUND_CONFIG" 2>&1 | grep -q "no errors"; then
    echo "✓ Configuration is valid"
else
    echo "✗ Configuration has errors:"
    sudo "$UNBOUND_BIN"-checkconf "$UNBOUND_CONFIG"
    exit 1
fi
echo ""

# Step 5: Start Unbound
echo "Step 5: Starting Unbound..."
sudo "$UNBOUND_BIN" -c "$UNBOUND_CONFIG"

# Wait a moment and check if it started
sleep 2

if pgrep -x unbound > /dev/null; then
    echo "✓ Unbound started successfully"
    echo ""
    
    # Show status
    echo "Status:"
    sudo lsof -i :53 | grep unbound || echo "  Port 53: Listening"
    echo ""
    
    echo "Test DNS resolution:"
    echo "  dig @127.0.0.1 google.com"
    echo ""
else
    echo "✗ Failed to start Unbound"
    echo ""
    echo "Check logs:"
    echo "  log stream --predicate 'process == \"unbound\"' --level debug"
    exit 1
fi

echo "========================================="
echo "Unbound is running!"
echo "========================================="

# Step 6: Restart Colima if it was running before
if [ "$COLIMA_WAS_RUNNING" = true ]; then
    echo ""
    echo "Step 6: Restarting Colima..."
    echo "Colima was stopped to free port 53. Starting it back up..."
    colima start 2>/dev/null || lima start 2>/dev/null || true
    
    # Wait for Colima to start
    sleep 3
    
    if colima status &>/dev/null && colima status | grep -q "Running"; then
        echo "✓ Colima restarted successfully"
    else
        echo "⚠️  Colima may not have started properly. Check with: colima status"
    fi
    echo ""
    echo "========================================="
    echo "Setup complete!"
    echo "========================================="
fi
