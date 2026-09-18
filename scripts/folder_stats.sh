#!/bin/bash

MIN_SIZE="100MB"
SEEDBOX_DIRS=("/Volumes/storage/storage/seedbox/media/tv" "/Volumes/storage/storage/seedbox/media/movies")
TARGET_DIRS=()
CUSTOM_SEEDBOX=()
SKIP_SEEDBOX_CROSSREF=false
MODE="all" # "all", "media", "seedbox"

function show_usage() {
    echo "Usage: $0 [-s min_size] [-b seedbox_dir] [-m | -r | -n] [directory ...]"
    echo "  -s  Minimum file size to list (e.g. 10MB, 100MB, 1GB). Default: 100MB"
    echo "  -b  Custom seedbox directory (can be specified multiple times)"
    echo "  -m  Media audit only (check if media files are linked to seedbox)"
    echo "  -r  Reverse / Seedbox audit only (check if seedbox files are linked to media)"
    echo "  -n  Skip seedbox cross-reference (only check link count > 1 in target dir)"
    echo "  -h  Show this help message"
    echo ""
    echo "Default behavior: Full 2-way audit (Media Library & Seedbox Unlinked Downloads)"
    echo "Default target directory: /Volumes/storage/storage/media"
    echo "Default seedbox directories: /Volumes/storage/storage/seedbox/media/tv, /Volumes/storage/storage/seedbox/media/movies"
    exit 1
}

# Parse options
while getopts ":s:b:mrnh" opt; do
  case $opt in
    s) MIN_SIZE="$OPTARG" ;;
    b) CUSTOM_SEEDBOX+=("$OPTARG") ;;
    m) MODE="media" ;;
    r) MODE="seedbox" ;;
    n) SKIP_SEEDBOX_CROSSREF=true ;;
    h) show_usage ;;
    \?) echo "Invalid option -$OPTARG" >&2; show_usage ;;
  esac
done

shift $((OPTIND-1))

# If custom seedbox dirs were provided, use them
if [ ${#CUSTOM_SEEDBOX[@]} -gt 0 ]; then
    SEEDBOX_DIRS=("${CUSTOM_SEEDBOX[@]}")
fi

# Remaining arguments are target directories
if [ $# -gt 0 ]; then
    TARGET_DIRS=("$@")
else
    # Default target directory
    DEFAULT_MEDIA="/Volumes/storage/storage/media"
    if [ -d "$DEFAULT_MEDIA" ]; then
        TARGET_DIRS=("$DEFAULT_MEDIA")
    else
        echo "Error: No target directory specified and default '$DEFAULT_MEDIA' does not exist."
        show_usage
    fi
fi

# Validate target directories
VALID_TARGET_DIRS=()
for dir in "${TARGET_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        VALID_TARGET_DIRS+=("$(cd "$dir" && pwd)")
    else
        echo "Warning: Directory '$dir' does not exist, skipping."
    fi
done

if [ ${#VALID_TARGET_DIRS[@]} -eq 0 ]; then
    echo "Error: No valid target directories found."
    exit 1
fi

# Determine stat command format for macOS (BSD stat) vs Linux (GNU stat)
if stat -f "%l" "$0" >/dev/null 2>&1; then
    # BSD stat (macOS uses %N for filename path)
    STAT_CMD="stat -f %l:::%z:::%i:::%N"
else
    # GNU stat (Linux uses %n for filename path)
    STAT_CMD="stat -c %h:::%s:::%i:::%n"
fi

# Parse MIN_SIZE to bytes using awk
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

SEEDBOX_DATA_FILE=$(mktemp)
MEDIA_DATA_FILE=$(mktemp)
MEDIA_TMP_FILE=$(mktemp)
SEEDBOX_TMP_FILE=$(mktemp)

cleanup() {
    rm -f "$SEEDBOX_DATA_FILE" "$MEDIA_DATA_FILE" "$MEDIA_TMP_FILE" "$SEEDBOX_TMP_FILE"
}
trap cleanup EXIT

# Collect seedbox inodes if cross-referencing is enabled
SEEDBOX_ACTIVE=false
if [ "$SKIP_SEEDBOX_CROSSREF" = false ]; then
    VALID_SEEDBOX_DIRS=()
    for sdir in "${SEEDBOX_DIRS[@]}"; do
        if [ -d "$sdir" ]; then
            VALID_SEEDBOX_DIRS+=("$sdir")
        fi
    done

    if [ ${#VALID_SEEDBOX_DIRS[@]} -gt 0 ]; then
        SEEDBOX_ACTIVE=true
        echo "Indexing seedbox inodes from source of truth..."
        find "${VALID_SEEDBOX_DIRS[@]}" -type f -print0 | xargs -0 $STAT_CMD 2>/dev/null > "$SEEDBOX_DATA_FILE"
    else
        echo "Note: Seedbox directories not found/accessible. Falling back to basic link count check."
    fi
fi

echo "Indexing media files in: ${VALID_TARGET_DIRS[*]}"
find "${VALID_TARGET_DIRS[@]}" -type f -print0 | xargs -0 $STAT_CMD 2>/dev/null > "$MEDIA_DATA_FILE"
echo ""

# Scan data files and perform 2-way evaluation
awk -F':::' \
    -v seedbox_active="$SEEDBOX_ACTIVE" \
    -v mode="$MODE" \
    -v media_tmp="$MEDIA_TMP_FILE" \
    -v seedbox_tmp="$SEEDBOX_TMP_FILE" \
    -v min_bytes="$MIN_SIZE_BYTES" '
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
    total_seedbox_size = 0
    clean_seedbox_size = 0
    unlinked_seedbox_size = 0

    total_media_size = 0
    clean_media_size = 0
    concrete_media_size = 0
    missing_seedbox_size = 0
}

# Pass 1: Process Seedbox data file
NR == FNR {
    if (seedbox_active == "true") {
        nlink = $1
        size = $2
        ino = $3
        name = $4

        seedbox_inodes[ino] = 1
        sb_count++
        sb_nlink[sb_count] = nlink
        sb_size[sb_count] = size
        sb_ino[sb_count] = ino
        sb_name[sb_count] = name
        total_seedbox_size += size
    }
    next
}

# Pass 2: Process Media data file
{
    nlink = $1
    size = $2
    ino = $3
    name = $4

    media_inodes[ino] = 1
    total_media_size += size

    if (seedbox_active == "true") {
        if (ino in seedbox_inodes) {
            clean_media_size += size
        } else if (nlink > 1) {
            missing_seedbox_size += size
            if (size > min_bytes) {
                print size "|[NOT IN SEEDBOX]|" name >> media_tmp
            }
        } else {
            concrete_media_size += size
            if (size > min_bytes) {
                print size "|[NOT HARDLINKED]|" name >> media_tmp
            }
        }
    } else {
        if (nlink > 1) {
            clean_media_size += size
        } else {
            concrete_media_size += size
            if (size > min_bytes) {
                print size "|[NOT HARDLINKED]|" name >> media_tmp
            }
        }
    }
}

END {
    # Evaluate Seedbox files against Media inodes
    if (seedbox_active == "true") {
        for (i = 1; i <= sb_count; i++) {
            size = sb_size[i]
            ino = sb_ino[i]
            name = sb_name[i]

            if (ino in media_inodes) {
                clean_seedbox_size += size
            } else {
                unlinked_seedbox_size += size
                if (size > min_bytes) {
                    print size "|[UNLINKED IN SEEDBOX]|" name >> seedbox_tmp
                }
            }
        }
    }

    # Output Section 1: Media Library Audit
    if (mode == "all" || mode == "media") {
        print "=========================================================================="
        print "MEDIA LIBRARY AUDIT (Media Files vs Seedbox Source of Truth)"
        print "=========================================================================="
        printf "1 - Total media size scanned: %s\n", human_readable(total_media_size)
        if (seedbox_active == "true") {
            printf "2 - Size of files hardlinked to Seedbox (Clean): %s\n", human_readable(clean_media_size)
            printf "3 - Size of concrete files (Not hardlinked): %s\n", human_readable(concrete_media_size)
            printf "4 - Size of hardlinked files missing from Seedbox: %s\n", human_readable(missing_seedbox_size)
            printf "5 - Total uncleaned media disk space: %s\n", human_readable(concrete_media_size + missing_seedbox_size)
        } else {
            printf "2 - Size of hardlinked files: %s\n", human_readable(clean_media_size)
            printf "3 - Size of non-hardlinked files (Uncleaned): %s\n", human_readable(concrete_media_size)
        }
        print ""
    }

    # Output Section 2: Seedbox Audit
    if ((mode == "all" || mode == "seedbox") && seedbox_active == "true") {
        print "=========================================================================="
        print "SEEDBOX AUDIT (Unlinked Downloads Sitting in Seedbox)"
        print "=========================================================================="
        printf "1 - Total seedbox size scanned: %s\n", human_readable(total_seedbox_size)
        printf "2 - Size of seedbox files hardlinked to Media (Clean): %s\n", human_readable(clean_seedbox_size)
        printf "3 - Size of seedbox files NOT linked to Media (Unlinked): %s\n", human_readable(unlinked_seedbox_size)
        print ""
    }
}
' "$SEEDBOX_DATA_FILE" "$MEDIA_DATA_FILE"

# Print Media Uncleaned Files List
if [ "$MODE" = "all" ] || [ "$MODE" = "media" ]; then
    echo "Files in Media taking extra space (> $MIN_SIZE, sorted by size desc):"
    if [ -s "$MEDIA_TMP_FILE" ]; then
        sort -t'|' -k1,1rn "$MEDIA_TMP_FILE" | awk -F'|' '
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
            size = $1
            tag = $2
            name = $3
            printf "%-22s %s (%s)\n", tag, name, human_readable(size)
        }'
    else
        echo "None"
    fi
    echo ""
fi

# Print Seedbox Unlinked Files List
if [ "$SEEDBOX_ACTIVE" = true ] && ([ "$MODE" = "all" ] || [ "$MODE" = "seedbox" ]); then
    echo "Files in Seedbox NOT linked to Media (> $MIN_SIZE, sorted by size desc):"
    if [ -s "$SEEDBOX_TMP_FILE" ]; then
        sort -t'|' -k1,1rn "$SEEDBOX_TMP_FILE" | awk -F'|' '
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
            size = $1
            tag = $2
            name = $3
            printf "%-22s %s (%s)\n", tag, name, human_readable(size)
        }'
    else
        echo "None"
    fi
fi
