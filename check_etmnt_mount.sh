#!/bin/bash
set -euo pipefail

# Script to check if external hard disk drives are properly mounted
# Handles cases where paths appear in Finder but aren't actually mounted
# Supports automatic remediation with force eject and remount
# Optimized for large/slow external drives

DRIVES=("etmnt" "share" "bkp")
MOUNT_BASE="/Volumes"
FAILED_DRIVES=()
SCRIPT_NAME=$(basename "$0")
DOCKER_COMPOSE_PATH="./docker/docker-compose.yml"
DOCKER_STOPPED=false

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

echo "=== External Hard Disk Mount Checker ==="
echo "Timestamp: $(date)"
echo "Checking drives: ${DRIVES[*]}"
echo

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
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
}

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
    local df_info=$(df "$mount_path" 2>/dev/null | tail -n 1)
    if [ -z "$df_info" ] || echo "$df_info" | grep -q "No such file or directory"; then
        print_status "ERROR" "Not visible in df output"
        drive_ok=false
    else
        local available_space=$(echo "$df_info" | awk '{print $4}')
        print_status "OK" "df shows ${available_space}K available"
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


# Function to stop Docker Compose services with timeout
stop_docker_services() {
    if [ ! -f "$DOCKER_COMPOSE_PATH" ]; then
        print_status "WARNING" "Docker Compose file not found at $DOCKER_COMPOSE_PATH"
        return 1
    fi
    
    echo
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
    if [ "$DOCKER_STOPPED" != true ]; then
        return 0
    fi
    
    echo
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
    
    echo
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
    
    echo
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
    echo
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

# Main execution
echo "=== Phase 1: Checking all drives ==="
for drive in "${DRIVES[@]}"; do
    if ! check_drive_mount "$drive"; then
        FAILED_DRIVES+=("$drive")
    fi
    echo
done

# Summary of initial check
echo "=== Phase 1 Summary ==="
if [ ${#FAILED_DRIVES[@]} -eq 0 ]; then
    print_status "OK" "All drives are working correctly"
    exit 0
else
    print_status "ERROR" "Failed drives: ${FAILED_DRIVES[*]}"
fi

# Phase 2: Remediation
echo
echo "=== Phase 2: Attempting remediation ==="
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
    echo
    print_status "WARNING" "Individual drive fixes failed. Ejecting entire disk..."
    stop_docker_services
    
    if force_eject_entire_disk "${STILL_FAILED[0]}"; then
        # Try to remount all drives after entire disk ejection
        if attempt_remount_all_drives; then
            # Final verification - check that all drives are actually working
            echo
            echo "=== Final verification ==="
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
            exit 0
        else
            print_status "ERROR" "Still failing after full disk remount: ${FINAL_FAILED[*]}"
            exit 1
        fi
    else
        print_status "ERROR" "Failed to eject entire disk. Manual intervention required."
        exit 1
    fi
fi

print_status "OK" "All drive issues resolved"
exit 0
