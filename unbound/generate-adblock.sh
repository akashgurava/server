#!/bin/bash
# Script to generate ad blocking list for Unbound
# Usage: ./generate-adblock.sh

ADBLOCK_FILE="/opt/homebrew/etc/unbound/adblock.conf"
TEMP_FILE="/tmp/adblock_temp.txt"

echo "Generating ad blocking list for Unbound..."

# Download StevenBlack's hosts file (unified hosts + fakenews + gambling)
curl -s "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" > "$TEMP_FILE"

# Create header
cat > "$ADBLOCK_FILE" << 'EOF'
# Ad blocking configuration for Unbound
# Auto-generated on $(date)
# Source: StevenBlack's hosts
# Location: /opt/homebrew/etc/unbound/adblock.conf

server:
EOF

# Convert hosts format to Unbound format
# Skip comments, localhost, and empty lines
# Convert: 0.0.0.0 domain.com -> local-zone: "domain.com" always_nxdomain
grep "^0\.0\.0\.0" "$TEMP_FILE" | \
    awk '{print $2}' | \
    grep -v "^localhost" | \
    grep -v "^0\.0\.0\.0$" | \
    sort -u | \
    while read domain; do
        echo "    local-zone: \"$domain\" always_nxdomain"
    done >> "$ADBLOCK_FILE"

# Count blocked domains
BLOCKED_COUNT=$(grep -c "local-zone:" "$ADBLOCK_FILE")

echo "Generated $BLOCKED_COUNT blocked domains"
echo "Saved to: $ADBLOCK_FILE"
echo ""
echo "To apply changes, run:"
echo "  sudo unbound-control reload"

# Cleanup
rm -f "$TEMP_FILE"
