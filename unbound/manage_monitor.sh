#!/bin/bash
# Manage Unbound Monitor Service using launchctl
# Usage: ./manage_monitor.sh {install|start|stop|restart|uninstall|status|logs|follow}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/bin/unbound-monitor"
MONITOR_SCRIPT="$INSTALL_DIR/monitor_service.sh"
START_SCRIPT="$INSTALL_DIR/start_service.sh"
STOP_SCRIPT="$INSTALL_DIR/stop_service.sh"
PID_FILE="$INSTALL_DIR/monitor.pid"
LOG_FILE="$INSTALL_DIR/monitor.log"

# LaunchAgent configuration
LABEL="com.unbound.monitor"
PLIST_FILE="$HOME/Library/LaunchAgents/$LABEL.plist"
LAUNCHAGENTS_DIR="$HOME/Library/LaunchAgents"

# Function to check if monitor is running via launchctl
is_monitor_running() {
    launchctl list | grep -q "$LABEL"
}

# Function to check if plist is installed
is_plist_installed() {
    [ -f "$PLIST_FILE" ]
}

# Function to create plist file
create_plist() {
    echo "Creating LaunchAgent plist..."
    
    # Create LaunchAgents directory if it doesn't exist
    mkdir -p "$LAUNCHAGENTS_DIR"
    
    # Make sure monitor script is executable
    chmod +x "$MONITOR_SCRIPT"
    
    # Create plist file
    cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$MONITOR_SCRIPT</string>
        <string>--interval</string>
        <string>60</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>$LOG_FILE</string>
    
    <key>StandardErrorPath</key>
    <string>$LOG_FILE</string>
    
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>
</dict>
</plist>
EOF
    
    echo "✅ Created plist file: $PLIST_FILE"
}

# Function to check sudo configuration
check_sudo_config() {
    # Test if we can run lsof without password (one of the required commands)
    if sudo -n /usr/sbin/lsof -v >/dev/null 2>&1; then
        echo "✅ Passwordless sudo is configured"
        return 0
    fi
    
    # If we get here, passwordless sudo might not be configured
    echo "⚠️  WARNING: Could not verify passwordless sudo configuration"
    echo ""
    echo "The monitor requires passwordless sudo for Unbound commands."
    echo "Please ensure sudoers is configured as described in the README:"
    echo ""
    echo "  sudo visudo"
    echo ""
    echo "Add these lines (replace YOUR_USERNAME with your username):"
    echo "  YOUR_USERNAME ALL=(ALL) NOPASSWD: /opt/homebrew/sbin/unbound"
    echo "  YOUR_USERNAME ALL=(ALL) NOPASSWD: /opt/homebrew/sbin/unbound-checkconf"
    echo "  YOUR_USERNAME ALL=(ALL) NOPASSWD: /usr/sbin/lsof"
    echo "  YOUR_USERNAME ALL=(ALL) NOPASSWD: /usr/bin/pkill unbound"
    echo "  YOUR_USERNAME ALL=(ALL) NOPASSWD: /bin/kill"
    echo ""
    read -p "Continue anyway? [y/N]: " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
    return 0
}

# Function to copy scripts to system location
copy_scripts() {
    echo "Copying scripts to $INSTALL_DIR..."
    
    # Create directory
    if ! sudo mkdir -p "$INSTALL_DIR"; then
        echo "❌ Failed to create $INSTALL_DIR"
        return 1
    fi
    
    # Copy scripts
    if ! sudo cp "$SCRIPT_DIR/monitor_service.sh" "$INSTALL_DIR/"; then
        echo "❌ Failed to copy monitor_service.sh"
        return 1
    fi
    
    if ! sudo cp "$SCRIPT_DIR/start_service.sh" "$INSTALL_DIR/"; then
        echo "❌ Failed to copy start_service.sh"
        return 1
    fi
    
    if ! sudo cp "$SCRIPT_DIR/stop_service.sh" "$INSTALL_DIR/"; then
        echo "❌ Failed to copy stop_service.sh"
        return 1
    fi
    
    # Make executable
    sudo chmod +x "$INSTALL_DIR"/*.sh
    
    # Set ownership
    sudo chown -R "$(whoami):staff" "$INSTALL_DIR"
    
    echo "✅ Scripts copied successfully"
}

# Function to rotate log file
rotate_log() {
    if [ -f "$LOG_FILE" ]; then
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local backup_log="${LOG_FILE}.${timestamp}"
        echo "Rotating log file..."
        sudo mv "$LOG_FILE" "$backup_log" 2>/dev/null || true
        echo "Previous log saved to: $backup_log"
        
        # Keep only last 5 log files
        local log_dir=$(dirname "$LOG_FILE")
        local log_count=$(ls -1 "${LOG_FILE}".* 2>/dev/null | wc -l)
        if [ "$log_count" -gt 5 ]; then
            echo "Cleaning up old log files (keeping last 5)..."
            ls -1t "${LOG_FILE}".* | tail -n +6 | xargs sudo rm -f 2>/dev/null || true
        fi
    fi
}

# Function to install (load) the LaunchAgent
install_monitor() {
    if is_monitor_running; then
        echo "Monitor is already running"
        return 1
    fi
    
    echo "Installing Unbound monitor service..."
    echo ""
    
    # Check sudo configuration
    if ! check_sudo_config; then
        echo "Installation cancelled"
        return 1
    fi
    
    # Copy scripts to system location
    if ! copy_scripts; then
        echo "Installation cancelled"
        return 1
    fi
    
    # Rotate existing log
    rotate_log
    
    # Create plist if it doesn't exist
    if ! is_plist_installed; then
        create_plist
    fi
    
    # Load the LaunchAgent
    launchctl load "$PLIST_FILE"
    
    # Wait a moment and check if it started
    sleep 2
    
    if is_monitor_running; then
        echo "✅ Monitor installed and started successfully"
        echo "Service: $LABEL"
        echo "Install location: $INSTALL_DIR"
        echo "Log file: $LOG_FILE"
        echo ""
        echo "The monitor will:"
        echo "  - Start automatically on login"
        echo "  - Restart automatically if it crashes"
        echo "  - Check Unbound every 60 seconds"
        echo ""
        echo "Commands:"
        echo "  ./manage_monitor.sh status  - Check status"
        echo "  ./manage_monitor.sh logs    - View logs"
        echo "  ./manage_monitor.sh stop    - Stop monitor"
    else
        echo "❌ Failed to start monitor"
        echo "Check logs: $LOG_FILE"
        return 1
    fi
}

# Function to start monitor (load if not loaded)
start_monitor() {
    if is_monitor_running; then
        echo "Monitor is already running"
        return 0
    fi
    
    if ! is_plist_installed; then
        echo "Monitor not installed. Installing..."
        install_monitor
        return $?
    fi
    
    echo "Starting Unbound monitor service..."
    launchctl load "$PLIST_FILE"
    
    sleep 2
    
    if is_monitor_running; then
        echo "✅ Monitor started successfully"
        echo "Log file: $LOG_FILE"
    else
        echo "❌ Failed to start monitor"
        return 1
    fi
}

# Function to stop monitor
stop_monitor() {
    if ! is_monitor_running; then
        echo "Monitor is not running"
        return 1
    fi
    
    echo "Stopping Unbound monitor service..."
    launchctl unload "$PLIST_FILE"
    
    # Wait for it to stop
    sleep 2
    
    if ! is_monitor_running; then
        echo "✅ Monitor stopped successfully"
        echo "Note: It will restart on next login unless you uninstall it"
        echo "To permanently remove: ./manage_monitor.sh uninstall"
    else
        echo "❌ Failed to stop monitor"
        return 1
    fi
}

# Function to uninstall monitor
uninstall_monitor() {
    if is_monitor_running; then
        echo "Stopping monitor first..."
        launchctl unload "$PLIST_FILE" 2>/dev/null
        sleep 2
    fi
    
    if is_plist_installed; then
        echo "Removing LaunchAgent plist..."
        rm -f "$PLIST_FILE"
        echo "✅ LaunchAgent removed"
    fi
    
    # Remove installed scripts
    if [ -d "$INSTALL_DIR" ]; then
        echo "Removing installed scripts from $INSTALL_DIR..."
        sudo rm -rf "$INSTALL_DIR"
        echo "✅ Installed scripts removed"
    fi
    
    echo "✅ Monitor uninstalled successfully"
    echo "The monitor will not start automatically anymore"
}

# Function to show status
show_status() {
    echo "========================================="
    echo "Unbound Monitor Service Status"
    echo "========================================="
    echo ""
    
    # Check launchctl status
    if is_monitor_running; then
        echo "✅ Status: Running"
        
        # Get PID from launchctl
        PID_INFO=$(launchctl list | grep "$LABEL")
        PID=$(echo "$PID_INFO" | awk '{print $1}')
        
        if [ "$PID" != "-" ]; then
            echo "PID: $PID"
        fi
        
        echo "Service: $LABEL"
        echo "Log file: $LOG_FILE"
        
        # Check if plist is installed
        if is_plist_installed; then
            echo "LaunchAgent: Installed"
            echo "Auto-start: Enabled (runs on login)"
        fi
        
        echo ""
        
        # Show last few log entries
        if [ -f "$LOG_FILE" ]; then
            echo "Recent activity:"
            tail -5 "$LOG_FILE"
        fi
    else
        echo "❌ Status: Not running"
        
        if is_plist_installed; then
            echo "LaunchAgent: Installed (but not loaded)"
            echo "Plist file: $PLIST_FILE"
        else
            echo "LaunchAgent: Not installed"
        fi
    fi
    
    echo ""
}

# Function to show logs
show_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "No log file found"
        return 1
    fi
    
    if command -v less > /dev/null; then
        less +G "$LOG_FILE"
    else
        tail -50 "$LOG_FILE"
    fi
}

# Function to follow logs
follow_logs() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "No log file found"
        return 1
    fi
    
    echo "Following monitor logs (Ctrl+C to stop)..."
    tail -f "$LOG_FILE"
}

# Main script
case "${1:-}" in
    install)
        install_monitor
        ;;
    start)
        start_monitor
        ;;
    stop)
        stop_monitor
        ;;
    restart)
        stop_monitor
        rotate_log
        sleep 1
        start_monitor
        ;;
    uninstall)
        uninstall_monitor
        ;;
    status)
        show_status
        ;;
    logs)
        show_logs
        ;;
    follow)
        follow_logs
        ;;
    *)
        echo "Usage: $0 {install|start|stop|restart|uninstall|status|logs|follow}"
        echo ""
        echo "Commands:"
        echo "  install   - Install and start the monitor (auto-starts on login)"
        echo "  start     - Start the monitor service"
        echo "  stop      - Stop the monitor service (temporarily)"
        echo "  restart   - Restart the monitor service"
        echo "  uninstall - Permanently remove the monitor"
        echo "  status    - Show monitor status"
        echo "  logs      - View monitor logs"
        echo "  follow    - Follow monitor logs in real-time"
        echo ""
        echo "Note: Uses launchctl (LaunchAgent) for service management"
        echo "      Requires passwordless sudo configuration (see README)"
        exit 1
        ;;
esac
