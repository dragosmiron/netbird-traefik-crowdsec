# NetBird Docker Stack (with Traefik v3.6 & CrowdSec AppSec WAF)

Production-ready deployment configuration for self-hosting the [NetBird](https://netbird.io/) zero-trust mesh network, protected by **Traefik v3.6** with automatic Let's Encrypt TLS and **CrowdSec AppSec WAF**.

---

## Why Use This Stack vs. Standard Install?

| Feature | Standard Quickstart Install | This Hardened Stack |
| :--- | :--- | :--- |
| **Edge Protection** | Unprotected raw edge exposure | **CrowdSec AppSec WAF** drops malicious probes (`.env`, SQLi, API abuse) with 403 Forbidden |
| **TLS & gRPC** | Basic or manual reverse proxy | **Traefik v3.6** with automatic Let's Encrypt TLS & tuned zero-timeout gRPC streams |
| **Secrets & Keys** | Manual generation / plain secrets | **Zero-touch**: Cryptographic auth secrets, encryption keys, and bouncer tokens auto-generated |
| **OS Security** | Default OS settings | **`bootstrap-os.sh`** configures UFW firewall, Fail2ban 24h jail, and kernel hardening |
| **Reverse Proxy** | Manual configuration | **Built-in TCP passthrough** for NetBird's public resource ingress with automatic TLS-ALPN-01 |
| **Updates** | Risk of wiping containers/configs | **Safe in-place updates**: Preserves existing secrets, keys, and SQLite databases |

---

## Configuration Variables

Replace these generic placeholders with your real values during deployment:

| Variable | Description | Example Value | Where Used |
| :--- | :--- | :--- | :--- |
| `NETBIRD_DOMAIN` | NetBird management domain | `netbird.yourdomain.com` | Dashboard, gRPC & API endpoint |
| `LETSENCRYPT_EMAIL` | Admin email for TLS notices | `admin@yourdomain.com` | Let's Encrypt certificate registration |
| `203.0.113.10` | Public IPv4 of your VPS | `198.51.100.42` | DNS **A** record target |

---

## Quick Start (3 Steps)

### 1. DNS Setup
Add the DNS **A records** in your DNS provider (e.g. Cloudflare, Porkbun, Namecheap):

| Record Type | Host / Name | Target / IPv4 | Proxy Status *(Cloudflare)* | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **A** | `netbird` *(or `@`)* | `203.0.113.10` | **DNS only (Grey Cloud) ☁️** | Dashboard, gRPC, API & STUN |
| **A** *(Optional)* | `*.netbird` *(or `*`)* | `203.0.113.10` | **DNS only (Grey Cloud) ☁️** | Wildcard for NetBird's Reverse Proxy / Public Ingress |

> [!WARNING]
> Set records to **DNS only (Grey cloud)**. Cloudflare CDN proxying blocks raw UDP (STUN `3478/udp`, WireGuard `51820/udp`) and persistent gRPC streams.

### 2. Base OS Hardening (Run as root)
Prepares a fresh Ubuntu/Debian VPS with hardened SSH, UFW firewall, Fail2ban, and Docker:

```bash
# Optional: customize SSH port (default is 39422)
export SSH_PORT=39422
sudo bash bootstrap-os.sh
```

### 3. Deploy Stack
Clone to your target deployment directory (e.g. `/opt/netbird`) and run `deploy.sh`:

```bash
cd /opt/netbird
NETBIRD_DOMAIN="netbird.yourdomain.com" LETSENCRYPT_EMAIL="admin@yourdomain.com" ./deploy.sh
```

---

## Common Operations

### Safe In-Place Updates
Pull latest updates without touching existing secrets or wiping databases:
```bash
cd /opt/netbird && git pull && ./deploy.sh
```

### Update CrowdSec Security Rules & Threat Intelligence
Pull latest CVE scenarios, IP blocklists, and virtual patches with zero downtime:
```bash
./deploy.sh --update-rules
```

### Verify Health & WAF Protection
```bash
# Normal dashboard access returns 200 OK:
curl -ks -I https://netbird.yourdomain.com

# Malicious probe returns 403 Forbidden (dropped by CrowdSec AppSec WAF):
curl -ks -I https://netbird.yourdomain.com/.env
```

---

## Detailed Documentation

- [Security, Rate Limiting & Firewall Guide](docs/security.md)
- [NetBird Reverse Proxy (Public Resource Ingress) Setup](docs/reverse-proxy.md)
- [Backup & Disaster Recovery Guide](docs/backup-restore.md)

---

## Pinned Versions

- **NetBird Dashboard:** `netbirdio/dashboard:v2.92.0`
- **NetBird Server:** `netbirdio/netbird-server:0.80.0`
- **NetBird Reverse Proxy:** `netbirdio/reverse-proxy:0.80.0`
- **Traefik Reverse Proxy:** `traefik:v3.6`
- **CrowdSec IPS & WAF:** `crowdsecurity/crowdsec:v1.8.1`

---

## License

This project is licensed under the [MIT License](LICENSE).
