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

## Quick Commands

```bash
# Start Unbound
./start_service.sh

# Start with monitor (auto-restarts if crashes, runs on login)
# Note: Requires passwordless sudo setup (see Step 4a)
./manage_monitor.sh install

# Check monitor status
./manage_monitor.sh status

# View logs
./manage_monitor.sh logs
```

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
├── start_service.sh       # Start Unbound (handles port 53 conflicts)
├── stop_service.sh        # Stop Unbound
├── monitor_service.sh     # Background monitor (auto-restarts if Unbound crashes)
├── manage_monitor.sh      # Manage the monitor service (start/stop/status)
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
# Make start script executable
chmod +x start_service.sh

# Start Unbound (handles port 53 conflicts automatically)
./start_service.sh

# The script will:
# - Check if port 53 is in use
# - Offer to stop Colima/Lima if detected
# - Validate configuration
# - Start Unbound
```

**Note**: We don't use `brew services` because it conflicts with Colima on port 53.

### 4. (Optional) Enable Monitor Service

The monitor service runs in the background and automatically restarts Unbound if it crashes. It uses macOS LaunchAgent for proper service management.

#### Step 4a: Configure Passwordless Sudo

Since Unbound requires sudo to start/stop, we need to configure passwordless sudo for specific commands:

```bash
# Edit sudoers file (use visudo for safety)
sudo visudo

# Add these lines at the end (replace YOUR_USERNAME with your actual username):
# Unbound monitor - passwordless sudo for specific commands
YOUR_USERNAME ALL=(ALL) NOPASSWD: /opt/homebrew/sbin/unbound
YOUR_USERNAME ALL=(ALL) NOPASSWD: /opt/homebrew/sbin/unbound-checkconf
YOUR_USERNAME ALL=(ALL) NOPASSWD: /usr/sbin/lsof
YOUR_USERNAME ALL=(ALL) NOPASSWD: /usr/bin/pkill unbound
YOUR_USERNAME ALL=(ALL) NOPASSWD: /bin/kill
```

**Example for user 'akash':**
```
akash ALL=(ALL) NOPASSWD: /opt/homebrew/sbin/unbound
akash ALL=(ALL) NOPASSWD: /opt/homebrew/sbin/unbound-checkconf
akash ALL=(ALL) NOPASSWD: /usr/sbin/lsof
akash ALL=(ALL) NOPASSWD: /usr/bin/pkill unbound
akash ALL=(ALL) NOPASSWD: /bin/kill
```

**Important:** Save and exit with `:wq` in visudo. It will validate the syntax.

#### Step 4b: Install Monitor

```bash
# Make manage script executable
chmod +x manage_monitor.sh

# Install and start the monitor (auto-starts on login)
./manage_monitor.sh install

# Check monitor status
./manage_monitor.sh status

# View monitor logs
./manage_monitor.sh logs

# Follow logs in real-time
./manage_monitor.sh follow
```

**Monitor features:**
- Uses macOS `launchctl` (LaunchAgent)
- Checks every 60 seconds if Unbound is running
- Automatically restarts Unbound using `--unattended` mode (no prompts)
- Checks if Unbound is responding to DNS queries
- Prevents restart loops (stops after 3 crashes in 5 minutes)
- Auto-starts on login (after installation)
- Auto-restarts if the monitor itself crashes (`KeepAlive: true`)
- Logs all activity to `monitor.log`

**To stop temporarily:**
```bash
./manage_monitor.sh stop
```

**To permanently remove:**
```bash
./manage_monitor.sh uninstall
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

### 3. Apply Changes

```bash
# Stop Unbound
./stop_service.sh

# Start Unbound with new config
./start_service.sh

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

# Restart Unbound
./stop_service.sh && ./start_service.sh
```

### Test Ad Blocking

```bash
# Test blocked domain
dig @127.0.0.1 doubleclick.net
# Should return NXDOMAIN
```

## Management Commands

### Start/Stop Unbound

```bash
# Start Unbound (interactive mode)
./start_service.sh

# Start Unbound (unattended mode - auto-answers yes to all prompts)
./start_service.sh --unattended

# Stop Unbound
./stop_service.sh

# Restart Unbound
./stop_service.sh && ./start_service.sh
```

### Monitor Service

```bash
# Install monitor (creates LaunchAgent, auto-starts on login)
./manage_monitor.sh install

# Start monitor (if already installed)
./manage_monitor.sh start

# Check if monitor is running
./manage_monitor.sh status

# View monitor logs
./manage_monitor.sh logs

# Follow logs in real-time
./manage_monitor.sh follow

# Stop monitor (temporarily - will restart on login)
./manage_monitor.sh stop

# Restart monitor
./manage_monitor.sh restart

# Uninstall monitor (permanently removes LaunchAgent)
./manage_monitor.sh uninstall
```

**LaunchAgent details:**
- Service name: `com.unbound.monitor`
- Plist location: `~/Library/LaunchAgents/com.unbound.monitor.plist`
- Runs as your user (requires passwordless sudo for Unbound commands)
- Auto-starts on login
- Auto-restarts if it crashes

### View Statistics

```bash
# Show current stats
sudo /opt/homebrew/sbin/unbound-control stats_noreset

# Show cache stats
sudo /opt/homebrew/sbin/unbound-control dump_cache | head -20
```

### Reload Configuration

```bash
# After changing unbound.conf (if Unbound is running)
sudo /opt/homebrew/sbin/unbound-control reload

# Or restart
./stop_service.sh && ./start_service.sh
```

### Flush Cache

```bash
# Flush specific domain
sudo /opt/homebrew/sbin/unbound-control flush firefox.225274.xyz

# Flush all cache
sudo /opt/homebrew/sbin/unbound-control flush_zone .
```

### View Logs

Unbound uses syslog for logging. View logs with these commands:

```bash
# Real-time logs (all levels)
log stream --predicate 'process == "unbound"' --level info

# Real-time logs (debug mode)
log stream --predicate 'process == "unbound"' --level debug

# Last hour of logs
log show --predicate 'process == "unbound"' --last 1h

# Only errors
log show --predicate 'process == "unbound"' --level error --last 1h

# Only DNS failures (SERVFAIL)
log show --predicate 'process == "unbound"' --level error --last 1h | grep SERVFAIL
```

**Current logging configuration:**
- `verbosity: 1` - Operational info (errors + warnings)
- `use-syslog: yes` - Logs to macOS system logs
- `log-queries: no` - Query logging disabled (for performance)
- `log-replies: no` - Reply logging disabled (for performance)
- `log-local-actions: no` - Local action logging disabled
- `log-servfail: yes` - DNS failures are logged

**To enable debug logging temporarily:**
1. Edit `/opt/homebrew/etc/unbound/unbound.conf`
2. Change `verbosity: 1` to `verbosity: 2` (or higher)
3. Set `log-queries: yes` and `log-replies: yes` if needed
4. Reload: `sudo /opt/homebrew/sbin/unbound-control reload`
5. Remember to revert after debugging!

### Check Status

```bash
# Check if Unbound is running
pgrep -x unbound

# Check what's using port 53
sudo lsof -i :53
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
# Use the start script (it handles port conflicts)
./start_service.sh

# Or manually check:
# Check config syntax
sudo /opt/homebrew/sbin/unbound-checkconf /opt/homebrew/etc/unbound/unbound.conf

# Check if port 53 is in use
sudo lsof -i :53

# Check logs
log stream --predicate 'process == "unbound"' --last 5m
```
### DNS not resolving

```bash
{{ ... }}
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
./stop_service.sh && ./start_service.sh
```

### Monthly Tasks

```bash
# Update Unbound
brew upgrade unbound

# Restart service
./stop_service.sh && ./start_service.sh
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
# Stop Unbound
./stop_service.sh

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
