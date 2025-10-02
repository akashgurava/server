#!/bin/bash
# Unbound DNS Server Setup Script
# Usage: ./setup.sh [--adblock]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/unbound.conf.template"
CONFIG_FILE="$SCRIPT_DIR/unbound.conf"
ENV_FILE="$SCRIPT_DIR/config.env"
ADBLOCK_FILE="$SCRIPT_DIR/adblock.conf"
ADBLOCK_ENABLED=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --adblock)
            ADBLOCK_ENABLED=true
            shift
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: ./setup.sh [--adblock]"
            exit 1
            ;;
    esac
done

echo "========================================="
echo "Unbound DNS Server Setup"
echo "========================================="
echo ""

# Step 1: Install Unbound
echo "Step 1: Installing Unbound..."
if [ -f "/opt/homebrew/sbin/unbound" ] || [ -f "/opt/homebrew/opt/unbound/sbin/unbound" ]; then
    echo "✓ Unbound is already installed"
else
    echo "Installing Unbound via Homebrew..."
    brew install unbound
    echo "✓ Unbound installed"
fi
echo ""

# Step 2: Setup Keys and Trust Anchor
echo "Step 2: Setting up keys and trust anchor..."

# Create directory if it doesn't exist
sudo mkdir -p /opt/homebrew/etc/unbound

# Generate DNSSEC trust anchor
if [ -f "/opt/homebrew/etc/unbound/root.key" ]; then
    echo "✓ DNSSEC trust anchor already exists"
else
    echo "Generating DNSSEC trust anchor..."
    sudo /opt/homebrew/sbin/unbound-anchor -a /opt/homebrew/etc/unbound/root.key
    echo "✓ DNSSEC trust anchor generated"
fi

# Generate control keys
if [ -f "/opt/homebrew/etc/unbound/unbound_server.key" ]; then
    echo "✓ Control keys already exist"
else
    echo "Generating control keys..."
    sudo /opt/homebrew/sbin/unbound-control-setup -d /opt/homebrew/etc/unbound
    echo "✓ Control keys generated"
fi
echo ""

# Step 3: Generate Configuration
echo "Step 3: Generating configuration..."

# Check if env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: Config file not found: $ENV_FILE"
    echo "Please create config.env with your settings"
    exit 1
fi

# Load variables from config.env
source "$ENV_FILE"

# Validate required variables
if [ -z "$DOMAIN" ] || [ -z "$LOCAL_SUBNET" ] || [ -z "$LOCAL_IP" ] || \
   [ -z "$TAILSCALE_SUBNET" ] || [ -z "$TAILSCALE_IP" ]; then
    echo "Error: Missing required variables in $ENV_FILE"
    echo "Required: DOMAIN, LOCAL_SUBNET, LOCAL_IP, TAILSCALE_SUBNET, TAILSCALE_IP"
    exit 1
fi

echo "Configuration:"
echo "  Domain: $DOMAIN"
echo "  Local: $LOCAL_SUBNET -> $LOCAL_IP"
echo "  Tailscale: $TAILSCALE_SUBNET -> $TAILSCALE_IP"

# Generate config from template
sed -e "s|__DOMAIN__|$DOMAIN|g" \
    -e "s|__LOCAL_SUBNET__|$LOCAL_SUBNET|g" \
    -e "s|__LOCAL_IP__|$LOCAL_IP|g" \
    -e "s|__TAILSCALE_SUBNET__|$TAILSCALE_SUBNET|g" \
    -e "s|__TAILSCALE_IP__|$TAILSCALE_IP|g" \
    "$TEMPLATE_FILE" > "$CONFIG_FILE"

echo "✓ Generated: $CONFIG_FILE"
echo ""

# Step 4: Generate Ad Blocking List (if enabled)
if [ "$ADBLOCK_ENABLED" = true ]; then
    echo "Step 4: Generating ad blocking list..."
    
    TEMP_FILE="/tmp/adblock_temp.txt"
    
    # Download StevenBlack's hosts file
    echo "Downloading blocklist..."
    curl -s "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts" > "$TEMP_FILE"
    
    # Create header
    cat > "$ADBLOCK_FILE" << 'EOF'
# Ad blocking configuration for Unbound
# Auto-generated
# Source: StevenBlack's hosts
# Location: /opt/homebrew/etc/unbound/adblock.conf

server:
EOF
    
    # Convert hosts format to Unbound format
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
    
    echo "✓ Generated $BLOCKED_COUNT blocked domains"
    
    # Cleanup
    rm -f "$TEMP_FILE"
    echo ""
else
    echo "Step 4: Skipping ad blocking (use --adblock to enable)"
    echo ""
fi

# Step 5: Deploy Configuration
echo "Step 5: Deploying configuration..."

# Copy generated config
echo "Copying configuration files..."
sudo cp "$CONFIG_FILE" /opt/homebrew/etc/unbound/unbound.conf
sudo cp "$ADBLOCK_FILE" /opt/homebrew/etc/unbound/adblock.conf

echo "✓ Configuration deployed"
echo ""

# Step 6: Verify Configuration
echo "Step 6: Verifying configuration..."
if sudo /opt/homebrew/sbin/unbound-checkconf /opt/homebrew/etc/unbound/unbound.conf 2>&1 | grep -q "no errors"; then
    echo "✓ Configuration is valid"
else
    echo "✗ Configuration has errors:"
    sudo /opt/homebrew/sbin/unbound-checkconf /opt/homebrew/etc/unbound/unbound.conf
    exit 1
fi
echo ""

# Done
echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "  1. Start Unbound:"
echo "     sudo brew services start unbound"
echo ""
echo "  2. Verify it's running:"
echo "     sudo brew services list | grep unbound"
echo ""
echo "  3. Test DNS resolution:"
echo "     dig @127.0.0.1 firefox.$DOMAIN"
echo ""
if [ "$ADBLOCK_ENABLED" = true ]; then
    echo "  4. Test ad blocking:"
    echo "     dig @127.0.0.1 doubleclick.net"
    echo ""
fi
