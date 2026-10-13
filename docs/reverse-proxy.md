# NetBird Reverse Proxy (Public Resource Ingress) Guide

NetBird includes an integrated Reverse Proxy allowing you to expose private machines and internal services securely to the internet without installing VPN client software on visitors' devices.

---

## Architecture

Traefik uses a catch-all TCP SNI passthrough rule:
```yaml
traefik.tcp.routers.proxy-passthrough.rule: HostSNI(`*`)
traefik.tcp.routers.proxy-passthrough.tls.passthrough: true
```
Any hostname that does not match `NETBIRD_DOMAIN` falls through directly to `netbird-proxy:8443`. The reverse proxy container automatically requests and provisions Let's Encrypt TLS certificates on demand using TLS-ALPN-01 challenges.

---

## Setup Steps

### 1. DNS Wildcard Record
Add a wildcard **A record** in your DNS provider pointing to your VPS public IPv4:
- **Type**: `A`
- **Name**: `*.netbird` (or `*`)
- **Target**: `Your VPS IPv4`
- **Proxy Status (Cloudflare)**: **DNS only (Grey Cloud) ☁️** *(Must NOT be proxied)*

### 2. Generate Cluster Token
1. Log into your NetBird admin dashboard at `https://netbird.yourdomain.com`.
2. Go to **Network** -> **Routing Peers** / **Reverse Proxy** (or **Access Control** -> **Resources**).
3. Click **Add Reverse Proxy** to generate a cluster token (`nbx_...`).

### 3. Apply Token
Update `proxy.env` on your server:
```bash
# Option A: In-place update
sed -i -e "s|^NB_PROXY_TOKEN=.*|NB_PROXY_TOKEN=nbx_YOUR_COPIED_TOKEN|g" proxy.env
docker compose restart proxy

# Option B: Pass via deploy.sh
NETBIRD_PROXY_TOKEN="nbx_YOUR_COPIED_TOKEN" ./deploy.sh
```

Any public resource you configure in the dashboard (e.g. `grafana.netbird.yourdomain.com`) will immediately route securely to the target internal peer with valid Let's Encrypt TLS.
