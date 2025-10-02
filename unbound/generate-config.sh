#!/bin/bash
# Generate Unbound configuration from template
# Usage: ./generate-config.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/unbound.conf.template"
CONFIG_FILE="$SCRIPT_DIR/unbound.conf"
ENV_FILE="$SCRIPT_DIR/config.env"

# Check if template exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file not found: $TEMPLATE_FILE"
    exit 1
fi

# Check if env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo "Error: Config file not found: $ENV_FILE"
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

echo "Generating Unbound configuration..."
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

# Validate configuration
echo ""
echo "Validating configuration..."
if sudo /opt/homebrew/sbin/unbound-checkconf "$CONFIG_FILE" 2>&1 | grep -q "no errors"; then
    echo "✓ Configuration is valid"
    echo ""
    echo "To apply changes:"
    echo "  sudo cp $CONFIG_FILE /opt/homebrew/etc/unbound/unbound.conf"
    echo "  sudo /opt/homebrew/sbin/unbound-control reload"
else
    echo "✗ Configuration has errors"
    sudo /opt/homebrew/sbin/unbound-checkconf "$CONFIG_FILE"
    exit 1
fi
