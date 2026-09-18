#!/bin/bash

# MKV File Analyzer Script
# Usage: ./mkv_analyzer.sh [path]
# Searches recursively for MKV files and displays their media information

# Function to convert bitrate to human readable format
format_bitrate() {
    local bitrate=$1
    if [ -z "$bitrate" ] || [ "$bitrate" = "N/A" ]; then
        echo "N/A"
        return
    fi
    
    # Convert to Mbps
    local mbps=$(echo "scale=1; $bitrate / 1000000" | bc 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$mbps" ]; then
        echo "${mbps}Mbps"
    else
        echo "N/A"
    fi
}

# Function to determine resolution
get_resolution() {
    local width=$1
    local height=$2
    
    # Check if height is a valid number
    if [[ ! "$height" =~ ^[0-9]+$ ]] || [ -z "$height" ]; then
        echo "Unknown"
        return
    fi
    
    if [ "$height" -ge 2160 ]; then
        echo "2160p"
    elif [ "$height" -ge 1440 ]; then
        echo "1440p"
    elif [ "$height" -ge 1080 ]; then
        echo "1080p"
    elif [ "$height" -ge 720 ]; then
        echo "720p"
    else
        echo "${height}p"
    fi
}

# Function to determine HDR type
get_hdr_type() {
    local color_transfer=$1
    local color_primaries=$2
    
    case "$color_transfer" in
        "smpte2084")
            if [ "$color_primaries" = "bt2020" ]; then
                echo "HDR10"
            else
                echo "HDR"
            fi
            ;;
        "arib-std-b67")
            echo "HLG"
            ;;
        "bt709"|"bt470m"|"bt470bg"|"smpte170m"|"smpte240m"|"linear"|"log"|"log-sqrt"|"iec61966-2-4"|"bt1361e"|"iec61966-2-1"|"bt2020-10"|"bt2020-12")
            echo "SDR"
            ;;
        *)
            echo "SDR"
            ;;
    esac
}

# Function to get Dolby Vision profile
get_dolby_vision() {
    local dv_profile=$1
    
    if [ -n "$dv_profile" ] && [ "$dv_profile" != "null" ]; then
        # Check if it's Profile 8.1 (which might show as 81 in some tools)
        if [ "$dv_profile" = "81" ]; then
            echo "Profile 8.1"
        else
            echo "Profile $dv_profile"
        fi
    else
        echo "None"
    fi
}

# Function to format codec name
format_codec() {
    local codec=$1
    
    case "$codec" in
        "hevc")
            echo "HEVC/H.265"
            ;;
        "h264")
            echo "H.264/AVC"
            ;;
        "av1")
            echo "AV1"
            ;;
        "vp9")
            echo "VP9"
            ;;
        "mpeg2video")
            echo "MPEG-2"
            ;;
        *)
            echo "$codec"
            ;;
    esac
}

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to show usage
show_usage() {
    echo "MKV Analyzer and Dolby Vision Converter"
    echo ""
    echo "Usage:"
    echo "  $0 [path]                    # Analyze MKV files"
    echo "  $0 --convert [path]          # Convert Profile 7 to Profile 8"
    echo "  $0 --test X [path]           # Create X-minute test and convert"
    echo ""
    echo "Options:"
    echo "  --convert                    Convert all Profile 7 files to Profile 8"
    echo "  --test X                     Create X-minute test files before conversion"
    echo "  --help                       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 /path/to/movies           # Analyze all MKV files"
    echo "  $0 --convert /path/to/movies # Convert all Profile 7 files"
    echo "  $0 --test 5 movie.mkv        # Create 5-minute test and convert"
    echo ""
    echo "Requirements for conversion:"
    echo "  - ffmpeg (video processing)"
    echo "  - dovi_tool (Dolby Vision conversion)"
    echo "  - mkvtoolnix (MKV creation)"
}

# Function to colorize resolution
colorize_resolution() {
    local resolution=$1
    case "$resolution" in
        "2160p")
            echo -e "${GREEN}${resolution}${NC}"
            ;;
        "1440p")
            echo -e "${YELLOW}${resolution}${NC}"
            ;;
        "1080p")
            echo -e "${RED}${resolution}${NC}"
            ;;
        *)
            echo -e "${BLUE}${resolution}${NC}"
            ;;
    esac
}

# Function to colorize HDR
colorize_hdr() {
    local hdr=$1
    local has_dv=$2
    
    # If Dolby Vision is present, HDR should be green
    if [ "$has_dv" = "true" ]; then
        echo -e "${GREEN}${hdr}${NC}"
        return
    fi
    
    case "$hdr" in
        "SDR"|"None")
            echo -e "${RED}${hdr}${NC}"
            ;;
        "HDR")
            echo -e "${YELLOW}${hdr}${NC}"
            ;;
        "HDR10"|"HLG")
            echo -e "${GREEN}${hdr}${NC}"
            ;;
        *)
            echo -e "${BLUE}${hdr}${NC}"
            ;;
    esac
}

# Function to colorize Dolby Vision
colorize_dolby_vision() {
    local dv=$1
    case "$dv" in
        "None")
            echo -e "${RED}${dv}${NC}"
            ;;
        "Profile 7")
            echo -e "${RED}${dv}${NC}"
            ;;
        "Profile 5"|"Profile 8"|"Profile 8.1")
            echo -e "${GREEN}${dv}${NC}"
            ;;
        *)
            echo -e "${BLUE}${dv}${NC}"
            ;;
    esac
}

# Function to get audio technology
get_audio_technology() {
    local codec=$1
    local profile=$2
    
    case "$codec" in
        "truehd")
            echo "Dolby"
            ;;
        "eac3"|"ac3")
            echo "Dolby"
            ;;
        "dts")
            echo "DTS"
            ;;
        "dca")
            echo "DTS"
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

# Function to get spatial audio format
get_spatial_audio() {
    local profile=$1
    local title=$2
    
    # Check profile first
    if [[ "$profile" == *"Atmos"* ]]; then
        echo "Dolby Atmos"
        return
    fi
    
    if [[ "$profile" == *"DTS:X"* ]]; then
        echo "DTS:X"
        return
    fi
    
    # Check title as fallback
    if [[ "$title" == *"Atmos"* ]]; then
        echo "Dolby Atmos"
        return
    fi
    
    if [[ "$title" == *"DTS:X"* ]]; then
        echo "DTS:X"
        return
    fi
    
    echo "No"
}

# Function to get audio format
get_audio_format() {
    local codec=$1
    local profile=$2
    
    case "$codec" in
        "truehd")
            echo "TrueHD"
            ;;
        "dts")
            if [[ "$profile" == *"MA"* ]] || [[ "$profile" == *"Master Audio"* ]]; then
                echo "DTS-HD MA"
            elif [[ "$profile" == *"HR"* ]] || [[ "$profile" == *"High Resolution"* ]]; then
                echo "DTS-HD HR"
            else
                echo "DTS"
            fi
            ;;
        "dca")
            echo "DTS"
            ;;
        "eac3")
            echo "E-AC-3"
            ;;
        "ac3")
            echo "AC-3"
            ;;
        "flac")
            echo "FLAC"
            ;;
        "pcm_s16le"|"pcm_s24le"|"pcm_s32le")
            echo "PCM"
            ;;
        *)
            echo "$codec"
            ;;
    esac
}

# Function to format audio channels
format_audio_channels() {
    local channels=$1
    local channel_layout=$2
    
    if [ -n "$channel_layout" ] && [ "$channel_layout" != "null" ]; then
        echo "$channel_layout"
    else
        case "$channels" in
            "1")
                echo "1.0"
                ;;
            "2")
                echo "2.0"
                ;;
            "6")
                echo "5.1"
                ;;
            "8")
                echo "7.1"
                ;;
            *)
                echo "${channels}.0"
                ;;
        esac
    fi
}

# Function to colorize audio technology
colorize_audio_technology() {
    local tech=$1
    case "$tech" in
        "DTS"|"Dolby")
            echo -e "${GREEN}${tech}${NC}"
            ;;
        "Unknown"|"No")
            echo -e "${RED}${tech}${NC}"
            ;;
        *)
            echo -e "${BLUE}${tech}${NC}"
            ;;
    esac
}

# Function to colorize spatial audio
colorize_spatial_audio() {
    local spatial=$1
    case "$spatial" in
        "Dolby Atmos"|"DTS:X")
            echo -e "${GREEN}${spatial}${NC}"
            ;;
        "No")
            echo -e "${RED}${spatial}${NC}"
            ;;
        *)
            echo -e "${BLUE}${spatial}${NC}"
            ;;
    esac
}

# Function to analyze a single audio stream
analyze_audio_stream() {
    local audio_stream_json=$1
    local stream_index=$2
    
    # Extract audio properties
    local audio_codec=$(echo "$audio_stream_json" | jq -r '.codec_name // empty' 2>/dev/null)
    local audio_profile=$(echo "$audio_stream_json" | jq -r '.profile // empty' 2>/dev/null)
    local audio_channels=$(echo "$audio_stream_json" | jq -r '.channels // empty' 2>/dev/null)
    local audio_channel_layout=$(echo "$audio_stream_json" | jq -r '.channel_layout // empty' 2>/dev/null)
    local audio_bitrate=$(echo "$audio_stream_json" | jq -r '.bit_rate // empty' 2>/dev/null)
    local audio_title=$(echo "$audio_stream_json" | jq -r '.tags.title // empty' 2>/dev/null)
    local audio_language=$(echo "$audio_stream_json" | jq -r '.tags.language // empty' 2>/dev/null)
    
    # Try BPS from tags if bit_rate is not available
    if [ -z "$audio_bitrate" ] || [ "$audio_bitrate" = "null" ]; then
        audio_bitrate=$(echo "$audio_stream_json" | jq -r '.tags.BPS // empty' 2>/dev/null)
    fi
    
    # Format audio output
    local audio_technology=""
    local audio_spatial=""
    local audio_format=""
    local audio_channels_formatted=""
    local audio_bitrate_formatted=""
    local audio_language_formatted=""
    
    if [ -n "$audio_codec" ] && [ "$audio_codec" != "null" ]; then
        audio_technology=$(get_audio_technology "$audio_codec" "$audio_profile")
        audio_spatial=$(get_spatial_audio "$audio_profile" "$audio_title")
        audio_format=$(get_audio_format "$audio_codec" "$audio_profile")
        audio_channels_formatted=$(format_audio_channels "$audio_channels" "$audio_channel_layout")
        
        # Format audio bitrate in kbps
        if [ -n "$audio_bitrate" ] && [ "$audio_bitrate" != "null" ] && [ "$audio_bitrate" != "empty" ]; then
            local kbps=$(echo "scale=0; $audio_bitrate / 1000" | bc 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$kbps" ]; then
                audio_bitrate_formatted="${kbps}kbps"
            else
                audio_bitrate_formatted="N/A"
            fi
        else
            audio_bitrate_formatted="N/A"
        fi
        
        # Format language
        if [ -n "$audio_language" ] && [ "$audio_language" != "null" ] && [ "$audio_language" != "empty" ]; then
            audio_language_formatted="$audio_language"
        else
            audio_language_formatted="unk"
        fi
    else
        audio_technology="Unknown"
        audio_spatial="No"
        audio_format="Unknown"
        audio_channels_formatted="N/A"
        audio_bitrate_formatted="N/A"
        audio_language_formatted="unk"
    fi
    
    # Colorize audio values
    local audio_technology_colored=$(colorize_audio_technology "$audio_technology")
    local audio_spatial_colored=$(colorize_spatial_audio "$audio_spatial")
    local audio_format_colored=$(echo -e "${BLUE}${audio_format}${NC}")
    local audio_channels_colored=$(echo -e "${BLUE}${audio_channels_formatted}${NC}")
    local audio_bitrate_colored=$(echo -e "${BLUE}${audio_bitrate_formatted}${NC}")
    local audio_language_colored=$(echo -e "${BLUE}${audio_language_formatted}${NC}")
    
    # Print audio track info
    echo -e "  Audio #$stream_index - Lang: $audio_language_colored Technology: $audio_technology_colored Spatial: $audio_spatial_colored Format: $audio_format_colored Channels: $audio_channels_colored Bitrate: $audio_bitrate_colored"
}

# Function to get chapter count
get_chapter_count() {
    local chapter_json=$1
    
    if [ -n "$chapter_json" ] && [ "$chapter_json" != "null" ]; then
        local count=$(echo "$chapter_json" | jq '.chapters | length' 2>/dev/null)
        if [ -n "$count" ] && [ "$count" -gt 0 ]; then
            echo "$count"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}

# Function to format file size
format_file_size() {
    local bytes=$1
    
    if [ -z "$bytes" ] || [ "$bytes" = "null" ] || [ "$bytes" = "empty" ]; then
        echo "N/A"
        return
    fi
    
    # Convert to appropriate unit
    if [ "$bytes" -ge 1048576 ]; then
        # MB
        local mb=$(echo "scale=1; $bytes / 1048576" | bc 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$mb" ]; then
            echo "${mb}MB"
        else
            echo "N/A"
        fi
    elif [ "$bytes" -ge 1024 ]; then
        # KB
        local kb=$(echo "scale=1; $bytes / 1024" | bc 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$kb" ]; then
            echo "${kb}KB"
        else
            echo "N/A"
        fi
    else
        echo "${bytes}B"
    fi
}

# Function to analyze subtitle streams
analyze_subtitles() {
    local subtitle_json=$1
    
    if [ -z "$subtitle_json" ] || [ "$subtitle_json" = "null" ]; then
        echo -e "  ${RED}No subtitle streams found${NC}"
        return
    fi
    
    local subtitle_count=$(echo "$subtitle_json" | jq '.streams | length' 2>/dev/null)
    if [ -z "$subtitle_count" ] || [ "$subtitle_count" -eq 0 ]; then
        echo -e "  ${RED}No subtitle streams found${NC}"
        return
    fi
    
    # Collect SRT subtitles
    local srt_languages=""
    local srt_count=0
    
    for ((i=0; i<subtitle_count; i++)); do
        local subtitle_stream=$(echo "$subtitle_json" | jq ".streams[$i]" 2>/dev/null)
        local codec=$(echo "$subtitle_stream" | jq -r '.codec_name // empty' 2>/dev/null)
        local language=$(echo "$subtitle_stream" | jq -r '.tags.language // empty' 2>/dev/null)
        local size_bytes=$(echo "$subtitle_stream" | jq -r '.tags.NUMBER_OF_BYTES // empty' 2>/dev/null)
        
        if [ "$codec" = "subrip" ]; then
            ((srt_count++))
            local formatted_size=$(format_file_size "$size_bytes")
            
            if [ -n "$language" ] && [ "$language" != "null" ] && [ "$language" != "empty" ]; then
                if [ -z "$srt_languages" ]; then
                    srt_languages="${language}(${formatted_size})"
                else
                    srt_languages="${srt_languages}, ${language}(${formatted_size})"
                fi
            else
                if [ -z "$srt_languages" ]; then
                    srt_languages="unk(${formatted_size})"
                else
                    srt_languages="${srt_languages}, unk(${formatted_size})"
                fi
            fi
        fi
    done
    
    # Display SRT subtitle information
    if [ $srt_count -gt 0 ]; then
        echo -e "  SRT Subtitles ($srt_count): ${BLUE}${srt_languages}${NC}"
    else
        echo -e "  SRT Subtitles: ${RED}None${NC}"
    fi
}

# Function to analyze a single MKV file
analyze_mkv() {
    local file_path="$1"
    
    # Check if file exists
    if [ ! -f "$file_path" ]; then
        echo "File: $file_path - Error: File does not exist"
        return
    fi
    
    local abs_path=$(realpath "$file_path" 2>/dev/null)
    if [ $? -ne 0 ]; then
        abs_path="$file_path"
    fi
    
    # Get file size
    local file_size=""
    if [ -f "$file_path" ]; then
        local size_bytes=$(stat -f%z "$file_path" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$size_bytes" ]; then
            file_size=$(format_file_size "$size_bytes")
        fi
    fi
    
    # Get video stream info
    local video_info=$(ffprobe -v quiet -select_streams v:0 -print_format json -show_streams "$file_path" 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$video_info" ]; then
        echo "File: $abs_path - Error: Could not analyze file"
        return
    fi
    
    # Get all audio streams info
    local all_audio_info=$(ffprobe -v quiet -select_streams a -print_format json -show_streams "$file_path" 2>/dev/null)
    
    # Get chapter info
    local chapter_info=$(ffprobe -v quiet -print_format json -show_chapters "$file_path" 2>/dev/null)
    
    # Get all subtitle streams info
    local all_subtitle_info=$(ffprobe -v quiet -select_streams s -print_format json -show_streams "$file_path" 2>/dev/null)
    
    # Extract video properties
    local width=$(echo "$video_info" | jq -r '.streams[0].width // empty' 2>/dev/null)
    local height=$(echo "$video_info" | jq -r '.streams[0].height // empty' 2>/dev/null)
    local codec=$(echo "$video_info" | jq -r '.streams[0].codec_name // empty' 2>/dev/null)
    local color_transfer=$(echo "$video_info" | jq -r '.streams[0].color_transfer // empty' 2>/dev/null)
    local color_primaries=$(echo "$video_info" | jq -r '.streams[0].color_primaries // empty' 2>/dev/null)
    local bitrate_tag=$(echo "$video_info" | jq -r '.streams[0].tags.BPS // empty' 2>/dev/null)
    local bitrate_stream=$(echo "$video_info" | jq -r '.streams[0].bit_rate // empty' 2>/dev/null)
    
    # Get Dolby Vision info from side data
    local dv_profile=$(echo "$video_info" | jq -r '.streams[0].side_data_list[]? | select(.side_data_type == "DOVI configuration record") | .dv_profile // empty' 2>/dev/null)
    
    # Use bitrate from tags first, then from stream
    local bitrate=""
    if [ -n "$bitrate_tag" ] && [ "$bitrate_tag" != "null" ]; then
        bitrate="$bitrate_tag"
    elif [ -n "$bitrate_stream" ] && [ "$bitrate_stream" != "null" ]; then
        bitrate="$bitrate_stream"
    fi
    
    # Get format info for overall bitrate if video bitrate not available
    if [ -z "$bitrate" ] || [ "$bitrate" = "null" ]; then
        local format_info=$(ffprobe -v quiet -print_format json -show_format "$file_path" 2>/dev/null)
        bitrate=$(echo "$format_info" | jq -r '.format.bit_rate // empty' 2>/dev/null)
    fi
    
    # Format video output
    local resolution=$(get_resolution "$width" "$height")
    local hdr_type=$(get_hdr_type "$color_transfer" "$color_primaries")
    local dv_info=$(get_dolby_vision "$dv_profile")
    local codec_formatted=$(format_codec "$codec")
    local bitrate_formatted=$(format_bitrate "$bitrate")
    
    # Check if Dolby Vision is present
    local has_dv="false"
    if [ -n "$dv_profile" ] && [ "$dv_profile" != "null" ] && [ "$dv_info" != "None" ]; then
        has_dv="true"
    fi
    
    # Colorize video values
    local resolution_colored=$(colorize_resolution "$resolution")
    local hdr_colored=$(colorize_hdr "$hdr_type" "$has_dv")
    local dv_colored=$(colorize_dolby_vision "$dv_info")
    local codec_colored=$(echo -e "${BLUE}${codec_formatted}${NC}")
    local bitrate_colored=$(echo -e "${BLUE}${bitrate_formatted}${NC}")
    
    # Get chapter count
    local chapter_count=$(get_chapter_count "$chapter_info")
    local chapter_count_colored=""
    if [ "$chapter_count" -gt 0 ]; then
        chapter_count_colored=$(echo -e "${BLUE}${chapter_count}${NC}")
    else
        chapter_count_colored=$(echo -e "${RED}${chapter_count}${NC}")
    fi
    
    # Print video output with chapters
    if [ -n "$file_size" ]; then
        echo -e "File: $abs_path (${file_size})"
    else
        echo -e "File: $abs_path"
    fi
    echo -e "Resolution: $resolution_colored HDR: $hdr_colored Dolby Vision: $dv_colored Codec: $codec_colored Bitrate: $bitrate_colored Chapters: $chapter_count_colored"
    
    # Process all audio streams
    if [ -n "$all_audio_info" ] && [ "$all_audio_info" != "null" ]; then
        local audio_count=$(echo "$all_audio_info" | jq '.streams | length' 2>/dev/null)
        if [ -n "$audio_count" ] && [ "$audio_count" -gt 0 ]; then
            for ((i=0; i<audio_count; i++)); do
                local audio_stream=$(echo "$all_audio_info" | jq ".streams[$i]" 2>/dev/null)
                analyze_audio_stream "$audio_stream" "$((i+1))"
            done
        else
            echo -e "  ${RED}No audio streams found${NC}"
        fi
    else
        echo -e "  ${RED}No audio streams found${NC}"
    fi
    
    # Process subtitle streams
    analyze_subtitles "$all_subtitle_info"
    
    echo ""
}

# Function to convert Profile 7 to Profile 8
convert_dv_profile() {
    local input_file="$1"
    local test_minutes="$2"
    local is_test_mode="$3"
    
    local base_name=$(basename "$input_file" .mkv)
    local dir_name=$(dirname "$input_file")
    local temp_dir="${dir_name}/.dv_conversion_temp"
    
    # Create temp directory
    mkdir -p "$temp_dir"
    
    echo -e "${YELLOW}Starting Dolby Vision Profile 7 to Profile 8 conversion...${NC}"
    
    # Step 1: Create test file if in test mode
    local working_file="$input_file"
    if [ "$is_test_mode" = "true" ]; then
        local test_file="${temp_dir}/${base_name}_test.mkv"
        echo -e "${BLUE}Creating ${test_minutes}-minute test file...${NC}"
        
        ffmpeg -i "$input_file" -t "${test_minutes}:00" -c copy -map 0 -avoid_negative_ts make_zero "$test_file" -y 2>/dev/null
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error: Failed to create test file${NC}"
            rm -rf "$temp_dir"
            return 1
        fi
        working_file="$test_file"
        
        echo -e "${GREEN}Test file created successfully${NC}"
    fi
    
    # Step 2: Extract video stream
    local raw_hevc="${temp_dir}/video.hevc"
    echo -e "${BLUE}Extracting video stream...${NC}"
    
    ffmpeg -i "$working_file" -c:v copy -bsf:v hevc_mp4toannexb -f rawvideo "$raw_hevc" -y 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to extract video stream${NC}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Step 3: Convert DV profile using dovi_tool
    local converted_hevc="${temp_dir}/video_p8.hevc"
    echo -e "${BLUE}Converting Dolby Vision Profile 7 to Profile 8...${NC}"
    
    # Mode 1: Converts the RPU to be MEL compatible (works with ONN 4K Plus 2025)
    dovi_tool --mode 1 convert -i "$raw_hevc" -o "$converted_hevc" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: dovi_tool conversion failed${NC}"
        echo -e "${RED}Make sure dovi_tool is installed and in PATH${NC}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Step 4: Create new MKV with converted video
    local suffix=""
    if [ "$is_test_mode" = "true" ]; then
        suffix="_test_p8"
        # Remove any existing _test suffix from base_name to avoid duplication
        base_name=$(echo "$base_name" | sed 's/_test$//')
    else
        suffix="_p8"
    fi
    
    local output_file="${dir_name}/${base_name}${suffix}.mkv"
    echo -e "${BLUE}Creating final MKV file...${NC}"
    
    # Use mkvmerge to combine converted video with original audio/subtitle streams
    # -D excludes video from working_file
    # -a 2 keeps only audio track 2 (E-AC-3), excludes TrueHD track 1
    mkvmerge -o "$output_file" "$converted_hevc" -D -a 2 "$working_file" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: mkvmerge failed to create final file${NC}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    echo -e "${GREEN}Conversion completed successfully!${NC}"
    echo -e "${GREEN}Output file: $output_file${NC}"
    echo ""
    
    # Show comparison stats
    if [ "$is_test_mode" = "true" ]; then
        echo -e "${YELLOW}=== COMPARISON: ORIGINAL (${test_minutes}-min test) vs CONVERTED ===${NC}"
        echo ""
        echo -e "${BLUE}ORIGINAL (TEST FILE):${NC}"
        analyze_mkv "$working_file"
        echo -e "${BLUE}CONVERTED FILE:${NC}"
        analyze_mkv "$output_file"
    else
        echo -e "${YELLOW}=== COMPARISON: ORIGINAL vs CONVERTED ===${NC}"
        echo ""
        echo -e "${BLUE}ORIGINAL FILE:${NC}"
        analyze_mkv "$input_file"
        echo -e "${BLUE}CONVERTED FILE:${NC}"
        analyze_mkv "$output_file"
    fi
    
    # Clean up temp files
    rm -rf "$temp_dir"
    
    return 0
}

# Function to check if file has Profile 7
has_profile_7() {
    local file_path="$1"
    local video_info=$(ffprobe -v quiet -select_streams v:0 -print_format json -show_streams "$file_path" 2>/dev/null)
    local dv_profile=$(echo "$video_info" | jq -r '.streams[0].side_data_list[]? | select(.side_data_type == "DOVI configuration record") | .dv_profile // empty' 2>/dev/null)
    
    if [ "$dv_profile" = "7" ]; then
        return 0
    else
        return 1
    fi
}

# Main script
main() {
{{ ... }}
    local test_minutes=""
    local is_test_mode=false
    local convert_mode=false
    
    # Show help if no arguments provided
    if [ $# -eq 0 ]; then
        show_usage
        exit 1
    fi
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_usage
                exit 0
                ;;
            --test)
                if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                    test_minutes="$2"
                    is_test_mode=true
                    convert_mode=true
                    shift 2
                else
                    echo "Error: --test requires a number of minutes"
                    echo ""
                    show_usage
                    exit 1
                fi
                ;;
            --convert)
                convert_mode=true
                shift
                ;;
            -*)
                echo "Error: Unknown option '$1'"
                echo ""
                show_usage
                exit 1
                ;;
            *)
                if [ -z "$search_path" ]; then
                    search_path="$1"
                else
                    echo "Error: Multiple paths specified. Only one path is allowed."
                    echo ""
                    show_usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Check if path was provided
    if [ -z "$search_path" ]; then
        echo "Error: Path is required"
        echo ""
        show_usage
        exit 1
    fi
    
    # Check if path exists
    if [ ! -e "$search_path" ]; then
        echo "Error: Path '$search_path' does not exist"
        exit 1
    fi
    
    # Check if required tools are available
    if ! command -v ffprobe >/dev/null 2>&1; then
        echo "Error: ffprobe is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is not installed or not in PATH"
        echo "Please install jq: brew install jq (on macOS) or apt-get install jq (on Ubuntu)"
        exit 1
    fi
    
    if ! command -v bc >/dev/null 2>&1; then
        echo "Error: bc is not installed or not in PATH"
        echo "Please install bc: brew install bc (on macOS) or apt-get install bc (on Ubuntu)"
        exit 1
    fi
    
    # Check for conversion tools if in convert mode
    if [ "$convert_mode" = true ]; then
        if ! command -v ffmpeg >/dev/null 2>&1; then
            echo "Error: ffmpeg is not installed or not in PATH (required for conversion)"
            exit 1
        fi
        
        if ! command -v dovi_tool >/dev/null 2>&1; then
            echo "Error: dovi_tool is not installed or not in PATH (required for DV conversion)"
            echo "Please install dovi_tool from: https://github.com/quietvoid/dovi_tool"
            exit 1
        fi
        
        if ! command -v mkvmerge >/dev/null 2>&1; then
            echo "Error: mkvmerge is not installed or not in PATH (required for MKV creation)"
            echo "Please install mkvtoolnix: brew install mkvtoolnix (on macOS)"
            exit 1
        fi
    fi
    
    if [ "$convert_mode" = true ]; then
        echo "Searching for Profile 7 MKV files in: $(realpath "$search_path")"
        echo "=================================================="
        echo ""
        
        # Find and process MKV files for conversion
        local count=0
        local converted_count=0
        while IFS= read -r -d '' file; do
            ((count++))
            
            if has_profile_7 "$file"; then
                echo -e "${YELLOW}=== ORIGINAL FILE STATS ===${NC}"
                analyze_mkv "$file"
                
                echo -e "${YELLOW}Found Profile 7 file: $file${NC}"
                
                if convert_dv_profile "$file" "$test_minutes" "$is_test_mode"; then
                    ((converted_count++))
                else
                    echo -e "${RED}Conversion failed for: $(basename "$file")${NC}"
                fi
                echo "=================================================="
                echo ""
            else
                echo -e "${BLUE}Skipping non-Profile 7 file: $(basename "$file")${NC}"
            fi
        done < <(find "$search_path" -type f -iname "*.mkv" -print0 2>/dev/null)
        
        if [ $count -eq 0 ]; then
            echo "No MKV files found in the specified path."
        else
            echo "Conversion complete. Found $count MKV file(s), converted $converted_count Profile 7 file(s)."
        fi
    else
        echo "Searching for MKV files in: $(realpath "$search_path")"
        echo "=================================================="
        echo ""
        
        # Find and analyze MKV files
        local count=0
        while IFS= read -r -d '' file; do
            analyze_mkv "$file"
            ((count++))
        done < <(find "$search_path" -type f -iname "*.mkv" -print0 2>/dev/null)
        
        if [ $count -eq 0 ]; then
            echo "No MKV files found in the specified path."
        else
            echo "Analysis complete. Found $count MKV file(s)."
        fi
    fi
}

# Check if script is being sourced or executed
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
