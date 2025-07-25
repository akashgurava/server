#!/bin/bash
set -euo pipefail

# Script to check if external hard disk drives are properly mounted
# Handles cases where paths appear in Finder but aren't actually mounted
# Supports automatic remediation with force eject and remount
# Optimized for large/slow external drives

# Default values
DRIVES=()
MOUNT_BASE="/Volumes"
FAILED_DRIVES=()
SCRIPT_NAME=$(basename "$0")
DOCKER_COMPOSE_PATH=""
DOCKER_STOPPED=false

# Logging configuration
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/ext_mount_$(date +%Y%m%d).log"
UNATTENDED_MODE=false
MONITOR_MODE=false
MONITOR_INTERVAL=0

# Function to log messages with timestamps
log_message() {
    local status=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$status] $message"
    echo "$log_entry" >> "$LOG_FILE"
}

# Function to print and log regular messages
print_and_log() {
    local message=$1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log to file
    echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
    
    # Print to console unless in unattended mode
    if [ "$UNATTENDED_MODE" != true ]; then
        echo "$message"
    fi
}

# Function to print colored output and log
print_status() {
    local status=$1
    local message=$2
    
    # Always log to file
    log_message "$status" "$message"
    
    # Print to console unless in unattended mode
    if [ "$UNATTENDED_MODE" != true ]; then
        case $status in
            "OK")
                echo -e "${GREEN}✅ $message${NC}"
                ;;
            "WARNING")
                echo -e "${YELLOW}⚠️  $message${NC}"
                ;;
            "ERROR")
                echo -e "${RED}❌ $message${NC}"
                ;;
        esac
    fi
}

# Function to print a new line in interactive mode
print_new_line() {
    if [ "$UNATTENDED_MODE" != true ]; then
        echo
    fi
}


# Function to show usage
show_usage() {
    echo "Usage: $SCRIPT_NAME --drives DRIVE1,DRIVE2,... [OPTIONS]"
    echo ""
    echo "Required arguments:"
    echo "  --drives DRIVES         Comma-separated list of drive names to monitor"
    echo "                          (e.g., --drives etmnt,share,bkp)"
    echo ""
    echo "Optional arguments:"
    echo "  --docker-compose PATH   Path to Docker Compose file (enables Docker integration)"
    echo "                          (e.g., --docker-compose ./docker/docker-compose.yml)"
    echo "  --mount-base PATH       Base mount directory (default: /Volumes)"
    echo "  --monitor SECONDS       Run in continuous monitoring mode with specified interval"
    echo "                          (e.g., --monitor 300 for 5-minute intervals)"
    echo "  --unattended           Run in unattended mode (log-only output, no console)"
    echo "  --help                 Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Basic usage without Docker integration"
    echo "  $SCRIPT_NAME --drives etmnt,share,bkp"
    echo "  "
    echo "  # With Docker integration"
    echo "  $SCRIPT_NAME --drives etmnt,share,bkp --docker-compose ./docker/docker-compose.yml"
    echo "  "
    echo "  # Different mount base (Linux systems)"
    echo "  $SCRIPT_NAME --drives media --mount-base /mnt"
    echo "  "
    echo "  # Continuous monitoring with 5-minute intervals"
    echo "  $SCRIPT_NAME --drives etmnt,share,bkp --monitor 300"
    echo "  "
    echo "  # Continuous monitoring with Docker integration and custom interval (30 seconds)"
    echo "  $SCRIPT_NAME --drives etmnt,share,bkp --docker-compose ./compose.yml --monitor 30 --unattended"
    echo ""
    echo "Log files are written to: $LOG_DIR/"
    echo "Current log file: $LOG_FILE"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --drives)
            if [[ -z "$2" ]]; then
                echo "Error: --drives requires a value"
                show_usage
                exit 1
            fi
            IFS=',' read -ra DRIVES <<< "$2"
            shift 2
            ;;
        --docker-compose)
            if [[ -z "$2" ]]; then
                echo "Error: --docker-compose requires a value"
                show_usage
                exit 1
            fi
            DOCKER_COMPOSE_PATH="$2"
            shift 2
            ;;
        --mount-base)
            if [[ -z "$2" ]]; then
                echo "Error: --mount-base requires a value"
                show_usage
                exit 1
            fi
            MOUNT_BASE="$2"
            shift 2
            ;;
        --monitor)
            if [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --monitor requires a positive integer value in seconds"
                show_usage
                exit 1
            fi
            MONITOR_MODE=true
            MONITOR_INTERVAL=$2
            shift 2
            ;;
        --unattended)
            UNATTENDED_MODE=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required arguments
if [[ ${#DRIVES[@]} -eq 0 ]]; then
    echo "Error: --drives is required"
    show_usage
    exit 1
fi

# Validate Docker Compose file exists (if provided)
if [[ -n "$DOCKER_COMPOSE_PATH" ]] && [[ ! -f "$DOCKER_COMPOSE_PATH" ]]; then
    echo "Error: Docker Compose file not found: $DOCKER_COMPOSE_PATH"
    exit 1
fi

# Validate drives exist in the system
print_and_log "Validating drives..."
for drive in "${DRIVES[@]}"; do
    # Check if drive exists using diskutil list (look for volume names)
    if ! diskutil list | grep -q "$drive"; then
        echo "Warning: Drive '$drive' not found in system. This may be expected if the drive is not currently connected."
        echo "Available volume names:"
        diskutil list | grep -E "[0-9]+:" | grep -v "EFI\|Recovery" | awk -F: '{print $2}' | awk '{print $1}' | grep -v "^$" | sort | uniq
        echo "Note: The script will still attempt to monitor this drive."
    else
        echo "✓ Drive '$drive' found in system"
    fi
done

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Configuration for slow/large drives
REMOUNT_RETRY_COUNT=5
REMOUNT_RETRY_DELAY=10  # seconds between retries
POST_EJECT_DELAY=8      # seconds to wait after ejection
MOUNT_CHECK_DELAY=5     # seconds to wait for mount operations
DOCKER_DOWN_TIMEOUT=60  # seconds to wait for docker compose down
DOCKER_UP_TIMEOUT=120   # seconds to wait for docker compose up

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Simple signal handling for monitor mode
trap 'log_message "INFO" "Received shutdown signal. Exiting..."; exit 0' SIGINT SIGTERM

# Function to check if a drive is properly mounted
check_drive_mount() {
    local drive_name=$1
    local mount_path="$MOUNT_BASE/$drive_name"
    local drive_ok=true
    
    echo "--- Checking $drive_name ---"
    
    # Check 1: Does the directory exist?
    if [ ! -d "$mount_path" ]; then
        print_status "ERROR" "Directory $mount_path does not exist"
        return 1
    fi
    
    # Check 2: Is it listed in mount output?
    local mount_info=$(mount | grep "$mount_path")
    if [ -z "$mount_info" ]; then
        print_status "ERROR" "Not found in mount table"
        drive_ok=false
    else
        local device=$(echo "$mount_info" | awk '{print $1}')
        print_status "OK" "Found in mount table: $device"
    fi
    
    # Check 3: Is it listed in df output?
    # Use df -H for human-readable sizes
    local df_info=$(df -H "$mount_path" 2>/dev/null | tail -n 1)
    if [ -z "$df_info" ] || echo "$df_info" | grep -q "No such file or directory"; then
        print_status "ERROR" "Not visible in df output"
        drive_ok=false
    else
        # On macOS, df -H output columns are: Filesystem, Size, Used, Avail, Capacity, iused, ifree, %iused, Mounted on
        local total_size=$(echo "$df_info" | awk '{print $2}')
        local available_size=$(echo "$df_info" | awk '{print $4}')
        
        # Extract numeric values (remove G, T, etc.)
        local total_size_num=$(echo "$total_size" | sed 's/[A-Za-z]//g')
        local available_size_num=$(echo "$available_size" | sed 's/[A-Za-z]//g')
        local size_unit=$(echo "$total_size" | sed 's/[0-9.]//g')
        
        # Add to totals (convert to GB if needed)
        if [[ "$size_unit" == "T" ]]; then
            # Convert TB to GB
            total_space=$(echo "scale=2; $total_space + ($total_size_num * 1000)" | bc 2>/dev/null || echo "$total_space")
            available_space=$(echo "scale=2; $available_space + ($available_size_num * 1000)" | bc 2>/dev/null || echo "$available_space")
        else
            # Already in GB or smaller
            total_space=$(echo "scale=2; $total_space + $total_size_num" | bc 2>/dev/null || echo "$total_space")
            available_space=$(echo "scale=2; $available_space + $available_size_num" | bc 2>/dev/null || echo "$available_space")
        fi
        
        print_status "OK" "df shows $available_size available (of $total_size)"
    fi
    
    # Check 4: Test for phantom mount (improved detection)
    local stat_info=$(stat -f "%d" "$mount_path" 2>/dev/null)
    local root_device_id=$(stat -f "%d" / 2>/dev/null)
    if [ "$stat_info" = "$root_device_id" ]; then
        # Additional check: verify this isn't a legitimate subdirectory
        local mount_point_check=$(mount | grep -c "$mount_path")
        local diskutil_check=$(diskutil info "$mount_path" 2>/dev/null | grep -c "Volume Name:" || echo "0")
        
        if [ "$mount_point_check" -eq 0 ] && [ "$diskutil_check" -eq 0 ]; then
            print_status "ERROR" "Phantom mount detected (same device ID as root, no mount entry)"
            drive_ok=false
        else
            print_status "WARNING" "Same device ID as root but appears to be legitimately mounted"
        fi
    fi
    
    # Check 5: Test read access and listing
    if ! ls "$mount_path" >/dev/null 2>&1; then
        print_status "ERROR" "Cannot list directory contents"
        drive_ok=false
    else
        local item_count=$(ls -la "$mount_path" 2>/dev/null | wc -l)
        print_status "OK" "Can list directory contents ($((item_count-1)) items)"
    fi
    
    # Check 6: Test write access (if possible)
    local test_file="$mount_path/.mount_test_$$"
    if touch "$test_file" 2>/dev/null; then
        print_status "OK" "Write access confirmed"
        rm -f "$test_file" 2>/dev/null
    else
        print_status "WARNING" "No write access (may be read-only or permission issue)"
    fi
    
    if [ "$drive_ok" = true ]; then
        print_status "OK" "$drive_name is working correctly"
        return 0
    else
        print_status "ERROR" "$drive_name has issues"
        return 1
    fi
}

# Function to get the parent disk of a volume
get_parent_disk() {
    local mount_path=$1
    diskutil info "$mount_path" 2>/dev/null | grep "Part of Whole:" | awk '{print $4}'
}

# Function to get Docker Compose service status
get_docker_service_status() {
    local compose_dir=$1
    local services_list=$(cd "$compose_dir" && docker compose ps --services --filter "status=running" 2>/dev/null)
    local running_count=$(echo "$services_list" | grep -c . 2>/dev/null || echo "0")
    local running_services=$(echo "$services_list" | tr '\n' ' ' | sed 's/ $//')
    
    # Handle empty case
    if [ -z "$services_list" ] || [ "$running_count" -eq 0 ]; then
        running_count=0
        running_services="none"
    fi
    
    echo "$running_count|$running_services"
}

# Function to get total expected services
get_total_services() {
    local compose_dir=$1
    cd "$compose_dir" && docker compose config --services 2>/dev/null | grep -c . || echo "0"
}

# Function to stop Docker Compose services
stop_docker_services() {
    # Skip if no Docker Compose file provided
    if [[ -z "$DOCKER_COMPOSE_PATH" ]]; then
        print_status "INFO" "No Docker Compose file provided, skipping Docker operations"
        return 0
    fi
    
    if [ "$DOCKER_STOPPED" = true ]; then
        print_status "WARNING" "Docker services already stopped"
        return 0
    fi
    
    if [ ! -f "$DOCKER_COMPOSE_PATH" ]; then
        print_status "WARNING" "Docker Compose file not found at $DOCKER_COMPOSE_PATH"
        return 1
    fi
    
    print_new_line
    print_status "WARNING" "Stopping Docker services before fixing etmnt drive..."
    print_status "WARNING" "This may take up to ${DOCKER_DOWN_TIMEOUT} seconds..."
    
    local compose_dir=$(dirname "$DOCKER_COMPOSE_PATH")
    local temp_log=$(mktemp)
    
    # Start docker compose down in background
    (cd "$compose_dir" && docker compose down) > "$temp_log" 2>&1 &
    local docker_pid=$!
    
    # Monitor by checking Docker Compose status
    local elapsed=0
    local check_interval=5
    local services_running=true
    
    # Check immediately first
    while [ $elapsed -lt $DOCKER_DOWN_TIMEOUT ] && [ "$services_running" = true ]; do
        # Get service status
        local status_info=$(get_docker_service_status "$compose_dir")
        local running_count=$(echo "$status_info" | cut -d'|' -f1)
        local running_services=$(echo "$status_info" | cut -d'|' -f2)
        
        if [ "$running_count" -eq 0 ]; then
            services_running=false
            print_status "OK" "All services stopped (took ${elapsed}s)"
        else
            print_status "WARNING" "$running_count services still running: $running_services (${elapsed}s/${DOCKER_DOWN_TIMEOUT}s)"
            # Only sleep if services are still running and we haven't timed out
            if [ $elapsed -lt $DOCKER_DOWN_TIMEOUT ]; then
                sleep $check_interval
                elapsed=$((elapsed + check_interval))
            fi
        fi
    done
    
    # Wait for the docker compose down process to complete
    if kill -0 $docker_pid 2>/dev/null; then
        wait $docker_pid 2>/dev/null || true
    fi
    
    # Final check
    local final_status=$(get_docker_service_status "$compose_dir")
    local final_running_count=$(echo "$final_status" | cut -d'|' -f1)
    local final_running_services=$(echo "$final_status" | cut -d'|' -f2)
    
    if [ "$final_running_count" -eq 0 ]; then
        print_status "OK" "Docker services stopped successfully"
        DOCKER_STOPPED=true
        rm -f "$temp_log"
        return 0
    else
        print_status "ERROR" "Docker compose down timed out - $final_running_count services still running: $final_running_services"
        print_status "WARNING" "Docker compose down output:"
        cat "$temp_log" 2>/dev/null || echo "No output available"
        rm -f "$temp_log"
        return 1
    fi
}

# Function to start Docker Compose services with timeout
start_docker_services() {
    # Skip if no Docker Compose file provided
    if [[ -z "$DOCKER_COMPOSE_PATH" ]]; then
        print_status "INFO" "No Docker Compose file provided, skipping Docker operations"
        return 0
    fi
    
    if [ "$DOCKER_STOPPED" != true ]; then
        return 0
    fi
    
    print_new_line
    print_status "WARNING" "Starting Docker services after fixing etmnt drive..."
    print_status "WARNING" "This may take up to ${DOCKER_UP_TIMEOUT} seconds..."
    
    local compose_dir=$(dirname "$DOCKER_COMPOSE_PATH")
    local temp_log=$(mktemp)
    
    # Start docker compose up in background
    (cd "$compose_dir" && docker compose up -d) > "$temp_log" 2>&1 &
    local docker_pid=$!
    
    # Monitor by checking Docker Compose status
    local elapsed=0
    local check_interval=5
    local target_services=$(get_total_services "$compose_dir")
    local services_ready=false

    print_status "WARNING" "Waiting for $target_services services to start..."
    
    # Check immediately first
    while [ $elapsed -lt $DOCKER_UP_TIMEOUT ] && [ "$services_ready" = false ]; do
        # Get service status
        local status_info=$(get_docker_service_status "$compose_dir")
        local running_count=$(echo "$status_info" | cut -d'|' -f1)
        local running_services=$(echo "$status_info" | cut -d'|' -f2)
        
        if [ "$running_count" -eq "$target_services" ] && [ "$target_services" -gt 0 ]; then
            services_ready=true
            print_status "OK" "All $target_services services are running: $running_services (took ${elapsed}s)"
        else
            print_status "WARNING" "$running_count/$target_services services running: $running_services (${elapsed}s/${DOCKER_UP_TIMEOUT}s)"
            # Only sleep if services aren't ready and we haven't timed out
            if [ $elapsed -lt $DOCKER_UP_TIMEOUT ]; then
                sleep $check_interval
                elapsed=$((elapsed + check_interval))
            fi
        fi
    done
    
    # Wait for the docker compose up process to complete
    if kill -0 $docker_pid 2>/dev/null; then
        wait $docker_pid 2>/dev/null || true
    fi
    
    # Final verification
    local final_status=$(get_docker_service_status "$compose_dir")
    local final_running_count=$(echo "$final_status" | cut -d'|' -f1)
    local final_running_services=$(echo "$final_status" | cut -d'|' -f2)
    
    if [ "$final_running_count" -gt 0 ]; then
        print_status "OK" "Docker services started successfully - $final_running_count containers running"
        print_status "OK" "Running services: $final_running_services"
        
        rm -f "$temp_log"
        return 0
    else
        print_status "ERROR" "Docker compose up failed - no services are running"
        print_status "WARNING" "Docker compose up output:"
        cat "$temp_log" 2>/dev/null || echo "No output available"
        rm -f "$temp_log"
        return 1
    fi
}

# Function to force eject a single drive
force_eject_drive() {
    local drive_name=$1
    local mount_path="$MOUNT_BASE/$drive_name"
    
    print_new_line
    print_status "WARNING" "Attempting to force eject $drive_name..."
    
    if diskutil unmount force "$mount_path" 2>/dev/null; then
        print_status "OK" "Successfully ejected $drive_name"
        return 0
    else
        print_status "ERROR" "Failed to eject $drive_name"
        return 1
    fi
}

# Function to eject entire external disk
force_eject_entire_disk() {
    local sample_drive=$1
    local mount_path="$MOUNT_BASE/$sample_drive"
    
    print_new_line
    print_status "WARNING" "Attempting to eject entire external disk..."
    
    # Get the parent disk identifier
    local parent_disk=$(get_parent_disk "$mount_path")
    if [ -z "$parent_disk" ]; then
        print_status "ERROR" "Cannot identify parent disk"
        return 1
    fi
    
    print_status "WARNING" "Ejecting disk: $parent_disk"
    if diskutil eject "$parent_disk" 2>/dev/null; then
        print_status "OK" "Successfully ejected entire disk $parent_disk"
        print_status "WARNING" "Waiting ${POST_EJECT_DELAY}s for system to process ejection of large/slow disk..."
        sleep $POST_EJECT_DELAY  # Wait for system to process the ejection
        return 0
    else
        print_status "ERROR" "Failed to eject entire disk $parent_disk"
        return 1
    fi
}

# Function to attempt mounting a single drive
attempt_mount_single_drive() {
    local drive=$1
    local mount_path="$MOUNT_BASE/$drive"
    
    print_status "WARNING" "Attempting to mount $drive..."
    
    local retry_count=0
    local mounted=false
    
    while [ $retry_count -lt $REMOUNT_RETRY_COUNT ] && [ "$mounted" = false ]; do
        # Try to mount the drive using diskutil
        if diskutil mount "$drive" >/dev/null 2>&1; then
            # Verify the mount was successful immediately
            if [ -d "$mount_path" ] && mount | grep -q "$mount_path"; then
                print_status "OK" "$drive mounted successfully (attempt $((retry_count + 1)))"
                mounted=true
                return 0
            else
                print_status "WARNING" "$drive mount command succeeded but verification failed"
            fi
        else
            print_status "WARNING" "diskutil mount $drive failed (attempt $((retry_count + 1)))"
        fi
        
        if [ "$mounted" = false ]; then
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $REMOUNT_RETRY_COUNT ]; then
                print_status "WARNING" "$drive not yet mounted, retrying in ${REMOUNT_RETRY_DELAY}s (attempt $retry_count/$REMOUNT_RETRY_COUNT)"
                sleep $REMOUNT_RETRY_DELAY
            fi
        fi
    done
    
    print_status "ERROR" "$drive failed to mount after $REMOUNT_RETRY_COUNT attempts"
    return 1
}

# Function to attempt remounting all drives (used after entire disk ejection)
attempt_remount_all_drives() {
    print_status "WARNING" "Attempting to remount all drives after entire disk ejection..."
    
    local failed_drives=()
    
    # Try to actively mount each drive
    for drive in "${DRIVES[@]}"; do
        if ! attempt_mount_single_drive "$drive"; then
            failed_drives+=("$drive")
        fi
    done
    
    if [ ${#failed_drives[@]} -eq 0 ]; then
        print_status "OK" "All drives remounted successfully"
        return 0
    else
        print_status "ERROR" "Failed to remount drives: ${failed_drives[*]}"
        return 1
    fi
}

# Function to perform a single mount check
perform_mount_check() {
    FAILED_DRIVES=()
    local check_start_time=$(date +%s)
    local total_space=0
    local available_space=0
    
    # Phase 1: Check all drives
    print_and_log "=== Phase 1: Checking all drives ==="
    for drive in "${DRIVES[@]}"; do
        if ! check_drive_mount "$drive"; then
            FAILED_DRIVES+=("$drive")
        fi
    done

    # Summary of initial check
    print_and_log "=== Phase 1 Summary ==="
    if [ ${#FAILED_DRIVES[@]} -eq 0 ]; then
        print_status "OK" "All drives are working correctly"
        
        # Add drive statistics summary
        print_and_log "Drive Statistics: Total space: ${total_space} GB, Available: ${available_space} GB"
        
        # Add timing information
        local check_end_time=$(date +%s)
        local check_duration=$((check_end_time - check_start_time))
        print_and_log "Check completed in ${check_duration} seconds"
        
        return 0
    else
        print_status "ERROR" "Failed drives: ${FAILED_DRIVES[*]}"
    fi

    print_and_log "=== Phase 2: Attempting remediation ==="
    # Try to fix individual drives first
    STILL_FAILED=()
    for drive in "${FAILED_DRIVES[@]}"; do
        # For etmnt drive Stop Docker services before attempting to fix
        if [ "$drive" = "etmnt" ]; then
            stop_docker_services
        fi

        if force_eject_drive "$drive"; then
            # Try to remount the individual drive
            if attempt_mount_single_drive "$drive"; then
                # Verify the drive is actually working properly
                if check_drive_mount "$drive" >/dev/null 2>&1; then
                    print_status "OK" "$drive fixed by individual remount"

                    # For etmnt drive Start Docker services after fixing
                    if [ "$drive" = "etmnt" ]; then
                        start_docker_services
                    fi
                else
                    print_status "WARNING" "$drive mounted but still has issues"
                    STILL_FAILED+=("$drive")
                    # No point in trying to fix other drives if any one drive is still failed
                    break
                fi
            else
                print_status "WARNING" "$drive failed to remount individually"
                STILL_FAILED+=("$drive")
                # No point in trying to fix other drives if any one drive is still failed
                break
            fi
        else
            STILL_FAILED+=("$drive")
            # No point in trying to fix other drives if any one drive is still failed
            break
        fi
    done

    # If any drives still failed, eject entire disk and remount all
    if [ ${#STILL_FAILED[@]} -gt 0 ]; then

        print_status "WARNING" "Individual drive fixes failed. Ejecting entire disk..."
        stop_docker_services
    
        if force_eject_entire_disk "${STILL_FAILED[0]}"; then
            # Try to remount all drives after entire disk ejection
            if attempt_remount_all_drives; then
                # Final verification - check that all drives are actually working
                print_new_line
                print_and_log "=== Final verification ==="
            FINAL_FAILED=()
                for drive in "${DRIVES[@]}"; do
                    if ! check_drive_mount "$drive" >/dev/null 2>&1; then
                        FINAL_FAILED+=("$drive")
                    fi
                done
            else
                # If remount failed, mark all drives as failed
                FINAL_FAILED=("${DRIVES[@]}")
            fi
        
            if [ ${#FINAL_FAILED[@]} -eq 0 ]; then
                print_status "OK" "All drives restored successfully"
                # Restart Docker services if they were stopped
                start_docker_services
                log_message "INFO" "=== External Hard Disk Mount Checker Completed Successfully ==="
                exit 0
            else
                print_status "ERROR" "Still failing after full disk remount: ${FINAL_FAILED[*]}"
                log_message "ERROR" "=== External Hard Disk Mount Checker Failed - Manual Intervention Required ==="
                exit 1
            fi
        else
            print_status "ERROR" "Failed to eject entire disk. Manual intervention required."
            log_message "ERROR" "=== External Hard Disk Mount Checker Failed - Disk Ejection Failed ==="
            exit 1
        fi
    fi

    print_status "OK" "All drive issues resolved"
    return 0
}


# Initialize logging
print_and_log "=== External Hard Disk Mount Checker Started ==="
print_and_log "Timestamp: $(date)"
print_and_log "Mode: $([ "$UNATTENDED_MODE" = true ] && echo "Unattended" || echo "Interactive")$([ "$MONITOR_MODE" = true ] && echo " (Monitor)" || echo "")"
print_and_log "Drives: ${DRIVES[*]}"
print_and_log "Mount base: $MOUNT_BASE"
if [[ -n "$DOCKER_COMPOSE_PATH" ]]; then
    print_and_log "Docker Compose: $DOCKER_COMPOSE_PATH (enabled)"
else
    print_and_log "Docker Compose: disabled"
fi
if [ "$MONITOR_MODE" = true ]; then
    print_and_log "Monitor interval: ${MONITOR_INTERVAL}s"
fi

# Main execution logic
if [ "$MONITOR_MODE" = true ]; then
    # Convert interval to minutes and seconds for display
    interval_minutes=$((MONITOR_INTERVAL / 60))
    interval_seconds=$((MONITOR_INTERVAL % 60))
    interval_display=""
    
    if [ $interval_minutes -gt 0 ]; then
        if [ $interval_minutes -eq 1 ]; then
            interval_display="$interval_minutes minute"
        else
            interval_display="$interval_minutes minutes"
        fi
        if [ $interval_seconds -gt 0 ]; then
            interval_display="$interval_display, $interval_seconds seconds"
        fi
    else
        interval_display="$interval_seconds seconds"
    fi
    
    # Monitor mode - continuous loop
    print_and_log "🔄 Starting continuous monitoring mode ($interval_display intervals)"
    print_and_log "Press Ctrl+C to stop monitoring"
    
    cycle_count=1
    
    while true; do
        print_and_log "==============================================="
        cycle_start=$(date)
        print_and_log "=== Monitor Cycle #$cycle_count Started. Timestamp: $cycle_start ==="
        
        # Perform the mount check
        if perform_mount_check; then
            log_message "INFO" "Monitor Cycle #$cycle_count completed successfully"
        else
            log_message "ERROR" "Monitor Cycle #$cycle_count failed"
        fi
        
        # Wait for next cycle
        if [ "$UNATTENDED_MODE" != true ]; then
            print_and_log "⏰ Waiting ${MONITOR_INTERVAL}s for next check..."
        else
            log_message "INFO" "Waiting ${MONITOR_INTERVAL}s for next monitor cycle"
        fi
        
        # Simple sleep - signal handler will interrupt if needed
        sleep $MONITOR_INTERVAL
        
        cycle_count=$((cycle_count + 1))
    done
else
    # Single-run mode
    if perform_mount_check; then
        log_message "INFO" "=== External Hard Disk Mount Checker Completed Successfully ==="
        exit 0
    else
        log_message "ERROR" "=== External Hard Disk Mount Checker Failed ==="
        exit 1
    fi
fi
