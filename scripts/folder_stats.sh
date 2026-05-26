#!/bin/bash

MIN_SIZE="100MB"
TARGET_DIR=""

function show_usage() {
    echo "Usage: $0 [-s min_size] <directory>"
    echo "  -s  Minimum file size to list (e.g. 10MB, 1GB). Default: 100MB"
    exit 1
}

# Parse arguments
while getopts ":s:" opt; do
  case $opt in
    s) MIN_SIZE="$OPTARG"
    ;;
    \?) echo "Invalid option -$OPTARG" >&2
    show_usage
    ;;
  esac
done

shift $((OPTIND-1))
TARGET_DIR="$1"

if [ -z "$TARGET_DIR" ]; then
    show_usage
fi

# Get absolute path to ensure full paths in output
if [ -d "$TARGET_DIR" ]; then
    TARGET_DIR=$(cd "$TARGET_DIR" && pwd)
else
    echo "Error: $TARGET_DIR is not a directory"
    exit 1
fi

# Parse MIN_SIZE to bytes using awk for robust handling
MIN_SIZE_BYTES=$(awk -v size="$MIN_SIZE" 'BEGIN {
    unit = toupper(size)
    val = size
    gsub(/[A-Z]+/, "", val)  # Extract number part
    
    mult = 1
    if (index(unit, "K") > 0) mult = 1024
    else if (index(unit, "M") > 0) mult = 1024^2
    else if (index(unit, "G") > 0) mult = 1024^3
    else if (index(unit, "T") > 0) mult = 1024^4
    else if (index(unit, "P") > 0) mult = 1024^5
    
    printf "%.0f", val * mult
}')

TMP_FILE=$(mktemp)

# Gather stats
# find: get all files
# stat: get link count (%l), size (%z), and name (%N)
# We use ':::' as a delimiter to handle spaces in filenames
find "$TARGET_DIR" -type f -print0 | xargs -0 stat -f "%l:::%z:::%N" | awk -F':::' -v tmp_file="$TMP_FILE" -v min_bytes="$MIN_SIZE_BYTES" '
function human_readable(bytes,    i, suffixes) {
    if (bytes == 0) return "0 B"
    split("B KB MB GB TB PB", suffixes, " ")
    i = 1
    while (bytes >= 1024 && i < 6) {
        bytes /= 1024
        i++
    }
    return sprintf("%.2f %s", bytes, suffixes[i])
}

BEGIN {
    total_size = 0
    hard_link_size = 0
}
{
    nlink = $1
    size = $2
    name = $3

    total_size += size
    if (nlink > 1) {
        hard_link_size += size
    } else {
        # Only list non-hardlinked files larger than min_bytes
        if (size > min_bytes) {
            # Print size and name to temp file for sorting
            # Format: size name
            print size, name >> tmp_file
        }
    }
}
END {
    printf "1 - Total size: %s\n", human_readable(total_size)
    printf "2 - Size of hard linked files: %s\n", human_readable(hard_link_size)
    printf "3 - Difference: %s\n", human_readable(total_size - hard_link_size)
}
'

echo "4 - Files that are not hardlinks (> $MIN_SIZE, sorted by size desc):"
if [ -s "$TMP_FILE" ]; then
    sort -rn -k1 "$TMP_FILE" | awk '
    function human_readable(bytes,    i, suffixes) {
        if (bytes == 0) return "0 B"
        split("B KB MB GB TB PB", suffixes, " ")
        i = 1
        while (bytes >= 1024 && i < 6) {
            bytes /= 1024
            i++
        }
        return sprintf("%.2f %s", bytes, suffixes[i])
    }
    {
        size=$1
        $1=""
        # Remove the leading space from $1=""
        sub(/^ /, "", $0)
        printf "%s (%s)\n", $0, human_readable(size)
    }'
else
    echo "None"
fi

rm "$TMP_FILE"
