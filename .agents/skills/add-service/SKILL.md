---
name: add-service
description: >-
  Guides adding new Docker services to the homelab server infrastructure.
  Use this skill whenever adding, migrating, or integrating a new containerized service,
  including Docker Compose configuration, static IP allocation, Traefik reverse proxy labels,
  environment variables, data volume paths, Unbound DNS records, and Cloudflare Tunnel routing.
---

# Adding a New Service to the Server

This guide provides the complete end-to-end workflow for adding a new service to this repository. All services follow standardized conventions for networking, persistence, reverse proxying, internal DNS, and external Cloudflare Tunnel routing.

---

## 1. Architecture & Allocation Standards

### Network IP Allocation Scheme
The Docker network is `server_network` (`172.18.0.0/16` and `2001:db8:1::/64`). Static IPs are partitioned by service category:

| Subnet Range | IPv6 Prefix | Category | Examples |
| :--- | :--- | :--- | :--- |
| `172.18.1.x` | `2001:db8:1::10x` | Core Edge & Monitoring | Traefik (`1.2`), Beszel (`1.3`) |
| `172.18.2.x` | `2001:db8:1::20x` / `22x` | Utilities | Filebrowser (`2.1`), Vaultwarden (`2.21`), WUD (`2.22`) |
| `172.18.3.x` | `2001:db8:1::30x` | AI & Language Models | 9Router (`3.1`) |
| `172.18.4.x` | `2001:db8:1::40x` | Media Stack | qBittorrent (`4.1`), Cross-Seed (`4.2`), Prowlarr (`4.4`), Radarr (`4.11`), Sonarr (`4.12`), Profilarr (`4.13`) |
| `172.18.5.x` | N/A | Dawarich Ecosystem | App (`5.1`), Sidekiq (`5.2`), Redis (`5.3`), DB (`5.4`) |

*Before picking an IP, check existing allocations across `docker/docker-compose-*.yml` to avoid collisions.*

### Domain & URL Conventions
All web services are exposed via subdomain:
`<service_name>.225274.xyz`

---

## 2. Step-by-Step Implementation Workflow

### Step 1: Define Environment Variables
Persistent paths are parameterized in `docker/.env` and mirrored in `docker/.env.example`.

1. Check the appropriate base directory variable:
   - AI: `LCL_AI_BASE=${LCL_CONFIG_DATA_BASE}/ai`
   - Media: `LCL_MEDIA_BASE=${LCL_CONFIG_DATA_BASE}/media`
   - Utilities: `LCL_UTILITIES_BASE=${LCL_CONFIG_DATA_BASE}/utilities`
   - Monitor: `LCL_MONITOR_BASE=${LCL_CONFIG_DATA_BASE}/monitor`
2. Add your service directory variable to `docker/.env`:
   ```env
   LCL_<SERVICE>_DATA=${LCL_<CATEGORY>_BASE}/<service>
   ```
3. Add the placeholder to `docker/.env.example`.

### Step 2: Create Persistent Host Directories
Create the data directory under `data/<category>/<service>`:
```bash
mkdir -p data/<category>/<service>
```

### Step 3: Configure Docker Compose
Open the relevant `docker/docker-compose-<category>.yml` (e.g. `docker-compose-ai.yml`, `docker-compose-utilities.yml`, or create a new one).

Follow this service template:
```yaml
services:
  # <Service Name>
  # Ports: <host_port>
  <service_name>:
    image: <image>:<tag>
    container_name: <service_name>
    hostname: <service_name>
    restart: unless-stopped
    networks:
      server_network:
        ipv4_address: 172.18.X.Y
        ipv6_address: 2001:db8:1::XY
    ports:
      - "<host_port>:<container_port>"
    volumes:
      - ${LCL_<SERVICE>_DATA}:/<container_path>
    environment:
      TZ: ${TZ}
    healthcheck:
      # Use 127.0.0.1 (not localhost) to prevent IPv6 connection refused on dual-stack server_network
      test: [ "CMD", "wget", "-q", "--tries=1", "--spider", "http://127.0.0.1:<container_port>/health" ]
      start_period: 10s
      interval: 30s
      timeout: 5s
      retries: 3
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.<service_name>.rule=Host(`<service_name>.225274.xyz`)"
      - "traefik.http.routers.<service_name>.entrypoints=websecure"
      - "traefik.http.routers.<service_name>.tls=true"
      - "traefik.http.services.<service_name>.loadbalancer.server.port=<container_port>"
      - "traefik.http.routers.<service_name>.tls.certresolver=letsencrypt"
```

### Step 4: Include in Main Docker Compose
If working with a new compose file (e.g., `docker-compose-<category>.yml`), ensure it is included in `docker/docker-compose.yml`:
```yaml
include:
  - docker-compose-utilities.yml
  - docker-compose-dawarich.yml
  - docker-compose-monitor.yml
  - docker-compose-media.yml
  - docker-compose-<category>.yml
```

### Step 5: Configure Unbound DNS
Update internal DNS in `unbound/unbound.conf` and `unbound/unbound.conf.template`:

In `unbound/unbound.conf`:
- **`local-view`**:
  ```conf
  local-data: "<service_name>.225274.xyz. IN A 192.168.1.2"
  ```
- **`tailscale-view`**:
  ```conf
  local-data: "<service_name>.225274.xyz. IN A 100.64.1.2"
  ```

In `unbound/unbound.conf.template`:
- **`local-view`**:
  ```conf
  local-data: "<service_name>.__DOMAIN__. IN A __LOCAL_IP_V4__"
  ```
- **`tailscale-view`**:
  ```conf
  local-data: "<service_name>.__DOMAIN__. IN A __TAILSCALE_IP_V4__"
  ```

### Step 6: Configure Cloudflare Tunnel (DNS & Ingress)
If the service should be reachable remotely through the Cloudflare Tunnel:

1. **Route DNS via `cloudflared` CLI**:
   ```bash
   cd .cloudflared
   cloudflared --config ./cloudflare.yml tunnel route dns --overwrite-dns 887b28ec-ae51-4b5f-a788-7c955f7d2eb2 <service_name>.225274.xyz
   ```

2. **Add ingress rule to `.cloudflared/cloudflare.yml`**:
   ```yaml
     # <Category>
     - hostname: <service_name>.225274.xyz
       service: http://127.0.0.1:<host_port>
   ```
   *(Ensure `127.0.0.1` is used instead of `localhost`, and `- service: http_status:404` remains at the very end).*

3. **Deploy configuration and restart daemon**:
   ```bash
   cd .cloudflared
   ./services.sh
   ```
   *(Validates YAML, copies to `/opt/homebrew/etc/cloudflared/`, and restarts the service via `launchctl`).*

---

## 3. Validation Checklist

Run the following commands to verify the configuration:

1. **Verify Docker Compose syntax & variable interpolation**:
   ```bash
   cd docker && docker compose config
   ```
2. **Verify directories and permissions**:
   ```bash
   ls -ld data/<category>/<service>
   ```
3. **Start the service (or test build)**:
   ```bash
   cd docker && docker compose up -d <service_name>
   ```
4. **Check container status & health**:
   ```bash
   docker ps --filter "name=<service_name>"
   docker logs --tail 20 <service_name>
   ```
5. **Verify host accessibility (Direct Port & Healthcheck)**:
   If the container exposes a host port:
   ```bash
   # Check raw HTTP response / headers from host
   curl -s -I http://127.0.0.1:<host_port>/

   # If service has a health endpoint
   curl -s http://127.0.0.1:<host_port>/api/health
   ```
6. **Verify Cloudflare DNS Routing & Public Ingress**:
   ```bash
   # 1. Verify Cloudflare Edge DNS resolution
   dig +short <service_name>.225274.xyz @1.1.1.1

   # 2. Test tunnel routing through Cloudflare Edge
   curl -s -I https://<service_name>.225274.xyz
   ```
7. **Verify Internal Unbound DNS**:
   ```bash
   dig @127.0.0.1 <service_name>.225274.xyz +short
   ```
