# Unbound DNS Server Setup

Complete setup guide for Unbound DNS server with split DNS and ad blocking on macOS.

## Overview

This setup provides:

- **Split DNS**: Returns different IPs based on client network (local vs Tailscale)
- **Ad Blocking**: Optional blocklist support via StevenBlack's hosts
- **DNSSEC**: Full validation enabled
- **DNS Forwarding**: Queries forwarded to Cloudflare DNS

## Current Status

✅ **Working** - Unbound is configured and running

## Network Configuration

### Local Network (192.168.1.0/24)

- Queries from local network return: `192.168.1.2`
- Example: `firefox.225274.xyz` → `192.168.1.2`

### Tailscale Network (100.64.0.0/10)

- Queries from Tailscale return: `100.64.1.2`
- Example: `firefox.225274.xyz` → `100.64.1.2`

### Other Networks

- Queries forwarded to Cloudflare DNS over TLS

## Files

```
unbound/
├── README.md              # This file
├── config.env             # Configuration variables (edit this!)
├── unbound.conf.template  # Configuration template
├── setup.sh               # Main setup script (installs, configures, deploys)
├── adblock.conf           # Ad blocking rules (optional)
└── .gitignore             # Excludes generated files
```

## Installation

### 1. Configure Variables

Edit `config.env` to set your IPs and domain:

```bash
nano config.env
```

Set these values:
```bash
DOMAIN="225274.xyz"
LOCAL_SUBNET="192.168.1.0/24"
LOCAL_IP="192.168.1.2"
TAILSCALE_SUBNET="100.64.0.0/10"
TAILSCALE_IP="100.64.1.2"
```

### 2. Run Setup Script

The setup script will:
- Install Unbound (if not installed)
- Generate DNSSEC trust anchor and control keys
- Generate configuration from template
- Deploy configuration
- Verify configuration

```bash
# Make script executable
chmod +x setup.sh

# Run setup (without ad blocking)
./setup.sh

# Or run with ad blocking enabled
./setup.sh --adblock
```

### 3. Start Unbound

```bash
# Start Unbound service
sudo brew services start unbound

# Verify it's running
sudo brew services list | grep unbound
# Should show: unbound started

# Check if listening on port 53
sudo lsof -i :53
# Should show unbound process
```

## Updating Configuration

When you need to change IPs or domain:

### 1. Edit Variables

```bash
# Edit config.env
nano config.env

# Change any values:
# LOCAL_IP="192.168.1.10"  # New IP
# TAILSCALE_IP="100.64.1.5"  # New Tailscale IP
```

### 2. Re-run Setup

```bash
# Re-run setup script (skips installation if already installed)
./setup.sh

# Or with ad blocking
./setup.sh --adblock
```

### 3. Reload Unbound

```bash
# Reload Unbound (no restart needed!)
sudo /opt/homebrew/sbin/unbound-control reload

# Test
dig @127.0.0.1 firefox.225274.xyz
```

**That's it!** All your services will now resolve to the new IP.

## Testing

### Test Split DNS

#### From Local Network (192.168.1.x):

```bash
# Check your current IP
ifconfig | grep "inet 192.168"

# Test DNS resolution
dig @127.0.0.1 firefox.225274.xyz
# Should return: 192.168.1.2

nslookup firefox.225274.xyz
# Should return: 192.168.1.2
```

#### From Tailscale Network (100.64.x.x):

```bash
# Check your Tailscale IP
ifconfig | grep "inet 100.64"

# Test DNS resolution
dig @127.0.0.1 firefox.225274.xyz
# Should return: 100.64.1.2

nslookup firefox.225274.xyz
# Should return: 100.64.1.2
```

### Test External DNS

```bash
# Test external domain resolution
dig @127.0.0.1 google.com
# Should resolve normally

# Test DNSSEC validation
dig @127.0.0.1 dnssec-failed.org
# Should fail with SERVFAIL
```

### Test HTTPS Access

```bash
# From local network
curl -k https://firefox.225274.xyz
# Should connect to 192.168.1.2

# From Tailscale
curl -k https://firefox.225274.xyz
# Should connect to 100.64.1.2
```

## Ad Blocking

Ad blocking is optional and can be enabled during setup.

### Enable Ad Blocking

```bash
# Run setup with --adblock flag
./setup.sh --adblock

# This will download ~100k+ domains from StevenBlack's hosts
```

### Update Blocklist

```bash
# Re-run setup with --adblock to update the list
./setup.sh --adblock

# Reload Unbound
sudo /opt/homebrew/sbin/unbound-control reload
```

### Test Ad Blocking

```bash
# Test blocked domain
dig @127.0.0.1 doubleclick.net
# Should return NXDOMAIN
```

## Management Commands

### View Statistics

```bash
# Show current stats
sudo /opt/homebrew/sbin/unbound-control stats_noreset

# Show cache stats
sudo /opt/homebrew/sbin/unbound-control dump_cache | head -20
```

### Reload Configuration

```bash
# After changing unbound.conf
sudo /opt/homebrew/sbin/unbound-control reload
```

### Flush Cache

```bash
# Flush specific domain
sudo /opt/homebrew/sbin/unbound-control flush firefox.225274.xyz

# Flush all cache
sudo /opt/homebrew/sbin/unbound-control flush_zone .
```

### View Logs

```bash
# View Unbound logs (syslog)
log stream --predicate 'process == "unbound"' --level debug

# Or check system logs
log show --predicate 'process == "unbound"' --last 1h
```

### Restart Unbound

```bash
# Restart service
sudo brew services restart unbound

# Check status
sudo brew services list | grep unbound
```

## Configuration Customization

### Add More Services

Edit `unbound.conf.template` and add to both views:

```conf
# In local-view section
local-data: "newservice.__DOMAIN__. IN A __LOCAL_IP__"

# In tailscale-view section
local-data: "newservice.__DOMAIN__. IN A __TAILSCALE_IP__"
```

Then regenerate and apply:

```bash
./setup.sh
sudo /opt/homebrew/sbin/unbound-control reload
```

### Change Upstream DNS

Edit `unbound.conf.template`, find the `forward-zone` section:

```conf
# Use Google DNS instead
forward-addr: 8.8.8.8@853#dns.google
forward-addr: 8.8.4.4@853#dns.google

# Or use Quad9
forward-addr: 9.9.9.9@853#dns.quad9.net
forward-addr: 149.112.112.112@853#dns.quad9.net
```

Then regenerate and apply:

```bash
./setup.sh
sudo /opt/homebrew/sbin/unbound-control reload
```

### Adjust Cache Size

Edit `unbound.conf.template`:

```conf
msg-cache-size: 100m      # Increase from 50m
rrset-cache-size: 200m    # Increase from 100m
```

Then regenerate and apply.

### Adjust Logging

Edit `unbound.conf.template`:

```conf
verbosity: 2              # Increase from 1 (more verbose)
log-queries: no           # Disable query logging
log-replies: no           # Disable reply logging
```

Then regenerate and apply.

## Troubleshooting

### Unbound won't start

```bash
# Check config syntax
sudo /opt/homebrew/sbin/unbound-checkconf /opt/homebrew/etc/unbound/unbound.conf

# Check if port 53 is in use
sudo lsof -i :53

# Check logs
log show --predicate 'process == "unbound"' --last 5m
```

### DNS not resolving

```bash
# Check if Unbound is running
sudo brew services list | grep unbound

# Check if system is using correct DNS
scutil --dns | grep nameserver

# Test directly
dig @127.0.0.1 google.com

# Flush DNS cache
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

### Split DNS not working

```bash
# Check your current IP
ifconfig | grep "inet "

# Verify you're in the correct subnet
# Local: 192.168.1.x
# Tailscale: 100.64.x.x

# Test with explicit server
dig @127.0.0.1 firefox.225274.xyz

# Check Unbound logs for view selection
log stream --predicate 'process == "unbound"' --level debug | grep view
```

### Permission errors

```bash
# Fix permissions on config files
sudo chown root:wheel /opt/homebrew/etc/unbound/unbound.conf
sudo chmod 644 /opt/homebrew/etc/unbound/unbound.conf

# Fix permissions on key files
sudo chmod 600 /opt/homebrew/etc/unbound/unbound_*.key
sudo chmod 644 /opt/homebrew/etc/unbound/unbound_*.pem
```

## Performance Tuning

For better performance on your Mac:

```conf
# Edit /opt/homebrew/etc/unbound/unbound.conf

# Adjust threads based on CPU cores (M1 has 8 cores)
num-threads: 4

# Increase cache
msg-cache-size: 100m
rrset-cache-size: 200m

# Enable prefetching
prefetch: yes
prefetch-key: yes

# Adjust TTL
cache-min-ttl: 300
cache-max-ttl: 86400
```

## Maintenance

### Weekly Tasks

```bash
# Update ad blocking list (if using ad blocking)
./setup.sh --adblock
sudo /opt/homebrew/sbin/unbound-control reload
```

### Monthly Tasks

```bash
# Update Unbound
brew upgrade unbound

# Restart service
sudo brew services restart unbound
```

### Backup Configuration

```bash
# Backup config files
sudo cp /opt/homebrew/etc/unbound/unbound.conf ~/unbound.conf.backup
sudo cp /opt/homebrew/etc/unbound/adblock.conf ~/adblock.conf.backup

# Backup keys
sudo cp /opt/homebrew/etc/unbound/unbound_*.{key,pem} ~/
```

## Uninstall

```bash
# Stop service
sudo brew services stop unbound

# Remove DNS configuration
sudo networksetup -setdnsservers Wi-Fi Empty

# Uninstall package
brew uninstall unbound

# Remove config files (optional)
sudo rm -rf /opt/homebrew/etc/unbound
```

## File Locations

- **Config**: `/opt/homebrew/etc/unbound/unbound.conf`
- **Ad Blocking**: `/opt/homebrew/etc/unbound/adblock.conf`
- **Trust Anchor**: `/opt/homebrew/etc/unbound/root.key`
- **Control Keys**: `/opt/homebrew/etc/unbound/unbound_*.{key,pem}`
- **Binary**: `/opt/homebrew/sbin/unbound`
- **Logs**: System logs (view with `log stream`)

## Useful Links

- [Unbound Documentation](https://nlnetlabs.nl/documentation/unbound/)
- [Unbound Configuration Reference](https://nlnetlabs.nl/documentation/unbound/unbound.conf/)
- [StevenBlack Hosts](https://github.com/StevenBlack/hosts)

## Next Steps

Now that Unbound is working:

1. ✅ DNS server with split DNS configured
2. ⏭️ Configure Traefik improvements
3. ⏭️ Set up authentication (Authelia/Authentik)

## Support

For issues or questions:

- Check the troubleshooting section above
- Review Unbound logs: `log stream --predicate 'process == "unbound"'`
- Test configuration: `sudo /opt/homebrew/sbin/unbound-checkconf`
