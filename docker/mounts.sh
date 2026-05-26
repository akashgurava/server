#!/bin/bash

echo "Remounting external USB/Thunderbolt drives..."

# List all disks to see what's available
echo "Available disks:"
diskutil list

echo ""
echo "Attempting to mount all unmounted external disks..."

# Find and mount all external disks
diskutil list | grep -E "(external|USB|Thunderbolt)" | while read line; do
    disk=$(echo $line | awk '{print $1}')
    if [[ $disk =~ ^/dev/disk[0-9]+s[0-9]+$ ]]; then
        echo "Attempting to mount $disk"
        diskutil mount $disk
    fi
done

# Also try to mount any unmounted APFS or HFS+ volumes
diskutil list | grep -E "(APFS|Apple_HFS)" | while read line; do
    disk=$(echo $line | awk '{print $NF}')
    if [[ $disk =~ ^disk[0-9]+s[0-9]+$ ]]; then
        echo "Attempting to mount /dev/$disk"
        diskutil mount "/dev/$disk"
    fi
done

echo ""
echo "Current mounted volumes:"
ls -la /Volumes/
