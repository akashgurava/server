# Cloudflare Tunnel

Manages the Cloudflare Tunnel daemon (`cloudflared`) on macOS to securely expose local services under `*.225274.xyz` without opening inbound router ports.

---

## Requirements

- **Homebrew**: `cloudflared` installed via `brew install cloudflared`.
- **Tunnel Credentials**: Active Cloudflare Tunnel credentials (`<tunnel-id>.json`) and certificate (`cert.pem`) placed in this directory.
- **Local Services**: Docker containers or host daemons listening on `127.0.0.1:<port>`.

---

## How to Run

### 1. Apply Changes & Restart Service

Run this script whenever you update `cloudflare.yml` or add a new service:

```bash
./services.sh
```

_(This automatically validates YAML syntax, rotates logs if >10MB, deploys config, and restarts the daemon via `launchctl`)._

### 2. How to Add a New Service

1. **Route DNS via CLI**:
   ```bash
   cloudflared --config ./cloudflare.yml tunnel route dns --overwrite-dns 887b28ec-ae51-4b5f-a788-7c955f7d2eb2 <subdomain>.225274.xyz
   ```
2. **Add ingress rule to `cloudflare.yml`**:
   ```yaml
   - hostname: <subdomain>.225274.xyz
     service: http://127.0.0.1:<port>
   ```
   _(Always use `127.0.0.1`, not `localhost`)._
3. **Deploy & restart**:
   ```bash
   ./services.sh
   ```

### 3. Check Status & Logs

```bash
# Check if running
ps aux | grep cloudflared | grep -v grep

# View live connection logs
tail -f /opt/homebrew/var/log/cloudflared.log

# Validate config syntax only
cloudflared tunnel --config ./cloudflare.yml ingress validate
```

### 4. Manual Start / Stop (via `launchctl`)

```bash
# Stop
launchctl bootout gui/$(id -u)/sh.brew.cloudflared

# Start
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/sh.brew.cloudflared.plist
```

> **Warning**: Do not use `brew services start/restart cloudflared`. Homebrew generates an empty plist with no arguments, causing `permission denied` crashes.

---

## Architecture & Design Notes

```
Users / Internet ──► Cloudflare Edge (SSL/DDoS) ──► Outbound QUIC Tunnel ──► `cloudflared` (macOS) ──► 127.0.0.1:<port>
```

- **Why `launchctl` instead of `brew services`?**
  Homebrew's formula hardcodes `ProgramArguments` to just `/opt/homebrew/opt/cloudflared/bin/cloudflared` without `--config`. When run bare, `cloudflared` attempts to create certs in `/etc/cloudflared/` as root and crashes with `permission denied`. Managing the plist directly via `launchctl` preserves the full startup flags.

- **Why `127.0.0.1` instead of `localhost`?**
  On macOS, `localhost` resolves to IPv6 `[::1]` first. Any local service or container bound only to IPv4 will trigger `read: connection reset by peer`. Explicit `127.0.0.1` forces IPv4 and prevents drops.

- **Why copy to `/opt/homebrew/etc/cloudflared/`?**
  Background daemons on macOS face permission restrictions when accessing user documents folders. Deploying the configuration into `/opt/homebrew/etc/cloudflared/` ensures the launchd agent can always read config files without sandbox issues.

---

## Troubleshooting

- **`HTTP 404`**: Hostname exists in Cloudflare DNS but is missing from `ingress:` in `cloudflare.yml`. Add it and run `./services.sh`.
- **`HTTP 502 Bad Gateway`**: Target container is stopped or not listening on that port. Check `docker ps`.
- **`read tcp [::1]:... connection reset by peer`**: Service is pointed to `localhost`. Change it to `127.0.0.1` in `cloudflare.yml`.
- **`permission denied`**: Someone ran `brew services restart`. Run `./services.sh` to reinstall the correct plist and restart.
