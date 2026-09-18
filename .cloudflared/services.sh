#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMEBREW_PREFIX="${HOMEBREW_PREFIX:-/opt/homebrew}"
USER_ID=$(id -u)
LABEL="sh.brew.cloudflared"
PLIST_TARGET="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOG_FILE="${HOMEBREW_PREFIX}/var/log/cloudflared.log"

echo "=== Step 1: Validating Cloudflare Ingress Configuration ==="
cloudflared tunnel --config "${SCRIPT_DIR}/cloudflare.yml" ingress validate
echo "✓ Configuration is valid."

echo ""
echo "=== Step 2: Managing Log File & Directories ==="
mkdir -p "${HOMEBREW_PREFIX}/etc/cloudflared"
mkdir -p "${HOME}/Library/LaunchAgents"
mkdir -p "${HOMEBREW_PREFIX}/var/log"

# Rotate log file if larger than 10MB (10485760 bytes)
if [ -f "$LOG_FILE" ]; then
    LOG_SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$LOG_SIZE" -gt 10485760 ]; then
        echo "Log file is $(($LOG_SIZE / 1024 / 1024))MB. Rotating to cloudflared.log.old..."
        mv -f "$LOG_FILE" "${LOG_FILE}.old"
        touch "$LOG_FILE"
        echo "✓ Log file rotated."
    fi
fi

echo ""
echo "=== Step 3: Deploying Configuration Files ==="
cp "${SCRIPT_DIR}/cloudflare.yml" "${HOMEBREW_PREFIX}/etc/cloudflared/cloudflare.yml"
cp "${SCRIPT_DIR}/887b28ec-ae51-4b5f-a788-7c955f7d2eb2.json" "${HOMEBREW_PREFIX}/etc/cloudflared/887b28ec-ae51-4b5f-a788-7c955f7d2eb2.json"
cp "${SCRIPT_DIR}/cert.pem" "${HOMEBREW_PREFIX}/etc/cloudflared/cert.pem"

# Also update cellar copies for reference if cellar exists
for version_dir in "${HOMEBREW_PREFIX}/Cellar/cloudflared"/*/; do
    if [ -d "$version_dir" ]; then
        cp "${SCRIPT_DIR}/cloudflared.plist" "$version_dir/sh.brew.cloudflared.plist" 2>/dev/null || true
        cp "${SCRIPT_DIR}/cloudflared.plist" "$version_dir/homebrew.mxcl.cloudflared.plist" 2>/dev/null || true
    fi
done

echo ""
echo "=== Step 4: Stopping Previous Service Instance ==="
brew services stop cloudflared 2>/dev/null || true
launchctl bootout "gui/${USER_ID}/${LABEL}" 2>/dev/null || true
launchctl bootout "gui/${USER_ID}/homebrew.mxcl.cloudflared" 2>/dev/null || true

echo ""
echo "=== Step 5: Installing Plist & Starting Service ==="
cp "${SCRIPT_DIR}/cloudflared.plist" "${PLIST_TARGET}"
launchctl enable "gui/${USER_ID}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/${USER_ID}" "${PLIST_TARGET}"

echo ""
echo "=== Step 6: Verifying Service Startup (waiting 6 seconds) ==="
sleep 6

# Check if process is running
PID=$(pgrep -f "cloudflared.*tunnel.*run" || true)
if [ -n "$PID" ]; then
    echo "✓ Cloudflared is running (PID: $PID)"
else
    echo "⚠ Warning: Cloudflared process not detected! Checking logs:"
    tail -n 20 "$LOG_FILE"
    exit 1
fi

echo ""
echo "=== Recent Cloudflared Logs ==="
tail -n 10 "$LOG_FILE"

echo ""
echo "✓ Cloudflared service successfully started and verified."
