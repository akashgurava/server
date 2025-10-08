#!/bin/bash
# Unbound Monitor Service
# Monitors Unbound and restarts it automatically if it stops
# Usage: ./monitor_service.sh [--interval SECONDS]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_INTERVAL=60  # Default: check every 60 seconds
PID_FILE="$SCRIPT_DIR/monitor.pid"
VERBOSE=false

# Source library functions
source "$SCRIPT_DIR/lib.sh"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--interval SECONDS] [--verbose]"
            echo ""
            echo "Options:"
            echo "  --interval SECONDS    Check interval (default: 60)"
            echo "  --verbose            Log every check (default: every 5 minutes)"
            echo "  --help               Show this help message"
            echo ""
            echo "To stop the monitor:"
            echo "  kill \$(cat $PID_FILE)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Function to log messages
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if monitor is already running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if ps -p "$OLD_PID" > /dev/null 2>&1; then
        echo "Monitor is already running (PID: $OLD_PID)"
        echo "To stop it: kill $OLD_PID"
        exit 1
    else
        # Stale PID file, remove it
        rm -f "$PID_FILE"
    fi
fi

# Save our PID
echo $$ > "$PID_FILE"

log "$(printf '=%.0s' {1..80})"
log "Unbound Monitor Service Started"
log "$(printf '=%.0s' {1..80})"
log "PID: $$"
log "Check interval: ${CHECK_INTERVAL}s"
log ""

# Cleanup on exit
cleanup() {
    log ""
    log "$(printf '=%.0s' {1..80})"
    log "Unbound Monitor Service Stopped"
    log "$(printf '=%.0s' {1..80})"
    rm -f "$PID_FILE"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Main monitoring loop
RESTART_COUNT=0
LAST_RESTART_TIME=0
LAST_LOG_TIME=0
LOG_INTERVAL=300  # Log healthy status every 5 minutes

while true; do
    if ! check_unbound_running; then
        log "$(printf '=%.0s' {1..80})"
        log "⚠️  Unbound is not running!"
        
        CURRENT_TIME=$(date +%s)
        
        # Only count as rapid restart if last restart attempt was less than 5 minutes ago
        if [ $LAST_RESTART_TIME -eq 0 ]; then
            # First restart attempt
            RESTART_COUNT=1
        else
            TIME_DIFF=$((CURRENT_TIME - LAST_RESTART_TIME))
            if [ $TIME_DIFF -ge 300 ]; then
                # More than 5 minutes since last attempt - reset counter
                log "ℹ️  Resetting restart counter (last attempt was ${TIME_DIFF}s ago)"
                RESTART_COUNT=1
            else
                # Rapid restart (less than 5 minutes) - increment counter
                RESTART_COUNT=$((RESTART_COUNT + 1))
                log "⚠️  Rapid restart detected (${TIME_DIFF}s since last attempt, count: $RESTART_COUNT)"
            fi
        fi
        
        # Update last restart attempt time
        LAST_RESTART_TIME=$CURRENT_TIME
        
        # Check if we're restarting too frequently (more than 3 rapid restarts)
        if [ $RESTART_COUNT -gt 3 ]; then
            log "$(printf '=%.0s' {1..80})"
            log "❌ ERROR: Unbound has crashed $RESTART_COUNT times rapidly (within 5 minutes)"
            log "❌ Stopping monitor to prevent restart loop"
            log "❌ Please investigate the issue manually"
            log "$(printf '=%.0s' {1..80})"
            cleanup
        fi
        
        log "🔄 Attempting to restart Unbound (rapid restart count: $RESTART_COUNT)..."
        
        # First, check if Colima is running
        COLIMA_WAS_RUNNING=false
        if check_colima_running; then
            log "🛑 Colima is running, stopping it to free port 53..."
            stop_colima
            COLIMA_WAS_RUNNING=true
            sleep 2
        fi
        
        # Then check if port 53 is still in use by something else
        PORT_CHECK=$(check_port_53)
        if [ -n "$PORT_CHECK" ]; then
            PROCESS_NAME=$(echo "$PORT_CHECK" | grep -v COMMAND | head -1 | awk '{print $1}')
            log "⚠️  Port 53 is still in use by another process"
            log "⚠️  Process: $PROCESS_NAME"
            log "⏳ Waiting ${CHECK_INTERVAL}s before retry..."
            log "$(printf '=%.0s' {1..80})"
            sleep "$CHECK_INTERVAL"
            continue
        fi
        
        # Validate config before attempting restart
        if ! validate_unbound_config; then
            log "❌ Configuration validation failed"
            log "$(printf '=%.0s' {1..80})"
            cleanup
        fi
        
        # Start Unbound using library function
        START_OUTPUT=$(start_unbound 2>&1)
        START_EXIT=$?
        
        if [ $START_EXIT -eq 0 ]; then
            # Wait and verify it's responding
            sleep 2
            if check_unbound_responding; then
                log "✅ Unbound restarted successfully"
                
                # Restart Colima if it was running before
                if [ "$COLIMA_WAS_RUNNING" = true ]; then
                    log "🔄 Restarting Colima..."
                    start_colima
                    if check_colima_running; then
                        log "✅ Colima restarted successfully"
                        
                        # Verify Unbound is still responding after Colima restart
                        sleep 2
                        if check_unbound_responding; then
                            log "✅ Unbound still responding after Colima restart"
                        else
                            log "⚠️  Unbound may have been affected by Colima restart"
                        fi
                    else
                        log "⚠️  Colima failed to restart"
                    fi
                fi
                
                log "$(printf '=%.0s' {1..80})"
            else
                log "⚠️  Unbound started but not responding to queries"
                log "$(printf '=%.0s' {1..80})"
            fi
        else
            log "❌ Failed to start Unbound"
            if [ -n "$START_OUTPUT" ]; then
                log "Error output: $START_OUTPUT"
            fi
            
            # If restart fails multiple times, stop the monitor
            if [ $RESTART_COUNT -ge 3 ]; then
                log "❌ ERROR: Failed to restart Unbound after $RESTART_COUNT attempts"
                log "❌ Stopping monitor - manual intervention required"
                log "$(printf '=%.0s' {1..80})"
                cleanup
            fi
            
            log "⏳ Will retry on next check cycle (${CHECK_INTERVAL}s)"
            log "$(printf '=%.0s' {1..80})"
            # Don't update LAST_RESTART_TIME so next attempt counts as rapid restart
        fi
    elif ! check_unbound_responding; then
        log "$(printf '=%.0s' {1..80})"
        log "⚠️  Unbound is running but not responding to queries"
        log "🔄 Restarting Unbound..."
        
        # Stop and start using library functions
        stop_unbound
        sleep 2
        
        if start_unbound; then
            sleep 2
            if check_unbound_responding; then
                log "✅ Unbound restarted and responding to queries"
                log "$(printf '=%.0s' {1..80})"
            else
                log "⚠️  Unbound restarted but still not responding"
                log "$(printf '=%.0s' {1..80})"
            fi
        else
            log "❌ Failed to restart Unbound"
            log "$(printf '=%.0s' {1..80})"
        fi
    else
        # Unbound is running and responding
        if [ "$VERBOSE" = true ]; then
            # In verbose mode, log every check
            log "✅ Unbound is running and responding to queries"
        else
            # In normal mode, log every 5 minutes
            CURRENT_TIME=$(date +%s)
            TIME_SINCE_LAST_LOG=$((CURRENT_TIME - LAST_LOG_TIME))
            
            if [ $TIME_SINCE_LAST_LOG -ge $LOG_INTERVAL ]; then
                log "✅ Unbound is running and responding to queries"
                LAST_LOG_TIME=$CURRENT_TIME
            fi
        fi
    fi
    
    # Wait for next check
    sleep "$CHECK_INTERVAL"
done
