#!/bin/bash
# Stop Unbound DNS Server

set -e

echo "========================================="
echo "Stopping Unbound DNS Server"
echo "========================================="
echo ""

# Check if Unbound is running
if pgrep -x unbound > /dev/null; then
    echo "Stopping Unbound..."
    sudo pkill unbound
    sleep 2
    
    # Verify it stopped
    if ! pgrep -x unbound > /dev/null; then
        echo "✓ Unbound stopped successfully"
    else
        echo "⚠️  Unbound may still be running"
        echo "Force kill? [y/N]: "
        read -n 1 -r
        echo ""
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo pkill -9 unbound
            echo "✓ Unbound force stopped"
        fi
    fi
else
    echo "Unbound is not running"
fi

echo ""
echo "========================================="
echo "Done"
echo "========================================="
