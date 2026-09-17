#!/bin/bash
# Unbound Dual-Stack & Split-Horizon Comprehensive Verification Suite

# Core Configuration Settings (Mirroring config.env values)
DOMAIN="225274.xyz"
LOCAL_IP_V4="192.168.1.2"
LOCAL_IP_V6="fdf7:2b9:374:0:14bc:d3c6:1169:6c5b"
TAILSCALE_IP_V4="100.64.1.2"
TAILSCALE_IP_V6="fd7a:1111:1111::1"

# ANSI Terminal Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "================================================================="
echo "       UNBOUND DUAL-STACK & VIEW COMPREHENSIVE SUITE             "
echo "================================================================="

# Comprehensive DNS Record Asserter
assert_dns() {
    local label="$1"
    local server="$2"
    local qdomain="$3"
    local qtype="$4"
    local expected_status="$5"
    local expected_pattern="$6"

    echo -n -e "Testing: [${qtype}] ${label}... "

    # Run dig without +short to preserve headers for status checks,
    # but capture full stdout and stderr securely.
    set +e
    output=$(dig @"$server" "$qdomain" "$qtype" +noedns 2>&1)
    status=$?
    set -e

    if [ $status -ne 0 ]; then
        echo -e "${RED}FAILED (dig execution error)${NC}"
        return 1
    fi

    # 1. Verify Header Status
    if ! echo "$output" | grep -q "status: $expected_status"; then
        echo -e "${RED}FAILED (Status Mismatch)${NC}"
        echo -e "  Expected status: ${YELLOW}$expected_status${NC}"
        echo "  --- Active Header ---"
        echo "$output" | grep -E "status:" || echo "$output"
        return 1
    fi

    # 2. Verify Payload Answer Pattern (Skip if checking purely for REFUSED/NXDOMAIN states)
    if [ -n "$expected_pattern" ]; then
        # Extract the section following the ANSWER SECTION header for clean regex evaluations
        local answer_block
        answer_block=$(echo "$output" | awk '/;; ANSWER SECTION:/{flag=1;next}/^$/{flag=0}flag')
        
        if ! echo "$answer_block" | grep -E -q "$expected_pattern"; then
            echo -e "${RED}FAILED (Answer Record Mismatch)${NC}"
            echo -e "  Expected Pattern: ${YELLOW}$expected_pattern${NC}"
            echo "  --- Active Answer Section ---"
            echo "$answer_block"
            return 1
        fi
    fi

    echo -e "${GREEN}PASSED${NC}"
    return 0
}

# --- STAGE 1: LOCAL LOOPBACK SYSTEM SANITY ---
echo -e "\n${BLUE}[STAGE 1: Local Loop Sanity via Localhost (127.0.0.1)]${NC}"

assert_dns \
    "IPv4 Public Forwarding (google.com)" \
    "127.0.0.1" "google.com" "A" \
    "NOERROR" "^google\.com\..*IN.*A"

assert_dns \
    "IPv6 Public Forwarding (google.com)" \
    "127.0.0.1" "google.com" "AAAA" \
    "NOERROR" "^google\.com\..*IN.*AAAA"

assert_dns \
    "Localhost Internal Pointer Resolution" \
    "127.0.0.1" "localhost" "A" \
    "NOERROR" "127\.0\.0\.1"


# --- STAGE 2: LOCAL LAN VIEW VALIDATION ---
echo -e "\n${BLUE}[STAGE 2: Local LAN View Validation (Matching local-view)]${NC}"

assert_dns \
    "LAN Split-Horizon Mapping" \
    "$LOCAL_IP_V4" "traefik.$DOMAIN" "A" \
    "NOERROR" "IN.*A.*$LOCAL_IP_V4"

assert_dns \
    "LAN IPv6 Dual-Stack Mapping" \
    "$LOCAL_IP_V4" "traefik.$DOMAIN" "AAAA" \
    "NOERROR" "IN.*AAAA.*$LOCAL_IP_V6"

assert_dns \
    "LAN Internal Domain Record Coverage" \
    "$LOCAL_IP_V4" "jellyfin.$DOMAIN" "A" \
    "NOERROR" "IN.*A.*$LOCAL_IP_V4"

assert_dns \
    "LAN Split-Horizon Fallback Forwarding (youtube.com)" \
    "$LOCAL_IP_V4" "youtube.com" "A" \
    "NOERROR" ""

assert_dns \
    "Android Captive Portal Endpoint Verification" \
    "$LOCAL_IP_V4" "connectivitycheck.gstatic.com" "A" \
    "NOERROR" ""


# --- STAGE 3: TAILSCALE MESH VIEW VALIDATION ---
echo -e "\n${BLUE}[STAGE 3: Tailscale View Validation (Matching tailscale-view)]${NC}"

# Verify host local interface availability before evaluating Tailscale view rules
if ifconfig | grep -q "$TAILSCALE_IP_V4" || tailscale status >/dev/null 2>&1; then
    assert_dns \
        "Tailscale Split-Horizon Mapping" \
        "$TAILSCALE_IP_V4" "traefik.$DOMAIN" "A" \
        "NOERROR" "IN.*A.*$TAILSCALE_IP_V4"

    assert_dns \
        "Tailscale IPv6 Dual-Stack Mapping" \
        "$TAILSCALE_IP_V4" "traefik.$DOMAIN" "AAAA" \
        "NOERROR" "IN.*AAAA.*$TAILSCALE_IP_V6"

    assert_dns \
        "Tailscale Internal Domain Record Coverage" \
        "$TAILSCALE_IP_V4" "jellyfin.$DOMAIN" "A" \
        "NOERROR" "IN.*A.*$TAILSCALE_IP_V4"

    assert_dns \
        "Tailscale Split-Horizon Fallback Forwarding" \
        "$TAILSCALE_IP_V4" "google.com" "A" \
        "NOERROR" ""
else
    echo -e "${YELLOW}Skipping Stage 3: Tailscale node address ($TAILSCALE_IP_V4) is unassigned or interface down.${NC}"
fi


# --- STAGE 4: SECURITY BOUNDARY CONTROL ---
echo -e "\n${BLUE}[STAGE 4: Security Boundary Control / ACL Verification]${NC}"
echo "Note: Simulating query sequence from an external untrusted network block..."

# Dynamically extract a valid, active IPv6 address from en0 that is NOT your allowed ULA
EXT_IPV6=$(ifconfig en0 | grep inet6 | grep -v 'fe80' | grep -v 'fdf7' | awk '{print $2}' | head -n 1)

if [ -z "$EXT_IPV6" ]; then
    echo -n "Testing: [A] Enforcement of Global Access Control Deny Posture... "
    echo -e "${YELLOW}SKIPPED (No secondary public IPv6 found on en0)${NC}"
else
    set +e
    # Bind the query to your public IPv6 address, targeting your local ULA Unbound server
    acl_output=$(dig @"$LOCAL_IP_V4" google.com -b "$EXT_IPV6" +noedns 2>&1)
    set -e

    echo -n "Testing: [A] Enforcement of Global Access Control Deny Posture (via source $EXT_IPV6)... "
    if echo "$acl_output" | grep -q "status: REFUSED"; then
        echo -e "${GREEN}PASSED${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        echo "  Security Boundary Breached or Improper Error Response Generation."
        echo "  --- Active Trace Output ---"
        echo "$acl_output" | grep "status:" || echo "$acl_output"
    fi
fi

echo -e "\n================================================================="
echo "Verification suite operations completed cleanly."
echo "================================================================="