#!/bin/bash
# Start Unbound DNS Server
# Handles port 53 conflicts with Colima/Lima

set -e

UNBOUND_BIN="/opt/homebrew/sbin/unbound"
UNBOUND_CONFIG="/opt/homebrew/etc/unbound/unbound.conf"

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

# Step 1: Check if anything is using port 53
echo "Step 1: Checking port 53..."
PORT_CHECK=$(sudo lsof -i :53 -sTCP:LISTEN 2>/dev/null || true)

if [ -n "$PORT_CHECK" ]; then
    echo "⚠️  Port 53 is already in use:"
    echo ""
    echo "$PORT_CHECK"
    echo ""
    
    # Extract process info
    PROCESS_INFO=$(echo "$PORT_CHECK" | grep -v COMMAND | head -1)
    PROCESS_NAME=$(echo "$PROCESS_INFO" | awk '{print $1}')
    PROCESS_PID=$(echo "$PROCESS_INFO" | awk '{print $2}')
    
    # Check if it's Colima or Lima
    if [[ "$PROCESS_NAME" == *"colima"* ]] || [[ "$PROCESS_NAME" == *"lima"* ]]; then
        echo "Detected Colima/Lima using port 53"
        echo ""
        read -p "Stop Colima/Lima? [Y/n]: " -n 1 -r
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            echo "Stopping Colima..."
            colima stop 2>/dev/null || lima stop 2>/dev/null || true
            echo "✓ Colima/Lima stopped"
            sleep 2
        else
            echo "Cannot start Unbound while port 53 is in use"
            exit 1
        fi
    else
        # Other process using port 53
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
    fi
else
    echo "✓ Port 53 is available"
fi
echo ""

# Step 2: Validate configuration
echo "Step 2: Validating configuration..."
if sudo "$UNBOUND_BIN"-checkconf "$UNBOUND_CONFIG" 2>&1 | grep -q "no errors"; then
    echo "✓ Configuration is valid"
else
    echo "✗ Configuration has errors:"
    sudo "$UNBOUND_BIN"-checkconf "$UNBOUND_CONFIG"
    exit 1
fi
echo ""

# Step 3: Check if Unbound is already running
echo "Step 3: Checking if Unbound is already running..."
if pgrep -x unbound > /dev/null; then
    echo "⚠️  Unbound is already running"
    read -p "Restart Unbound? [Y/n]: " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        echo "Stopping Unbound..."
        sudo pkill unbound || true
        sleep 2
        echo "✓ Unbound stopped"
    else
        echo "Unbound is already running"
        exit 0
    fi
fi
echo ""

# Step 4: Start Unbound
echo "Step 4: Starting Unbound..."
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
