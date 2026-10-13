# NetBird Docker Stack (with Traefik v3.6 & CrowdSec AppSec WAF)

Production-ready deployment configuration for self-hosting the [NetBird](https://netbird.io/) zero-trust mesh network, protected by **Traefik v3.6** with automatic Let's Encrypt TLS and **CrowdSec AppSec WAF**.

All secrets and cryptographic keys are **automatically generated** via `./deploy.sh` on fresh installs. Existing installations are automatically detected and safely updated without overwriting secrets or wiping databases.

---

## Architecture Overview

```text
                                  Internet
                                     │
                     [Port 80 / 443 / 3478 / 51820]
                                     ▼
                            Target Host / VPS
   ┌─────────────────────────────────────────────────────────────┐
   │ Traefik v3.6 Reverse Proxy                                  │
   │  ├── CrowdSec Traefik Bouncer (Stream Mode)                │
   │  ├── CrowdSec AppSec WAF (Port 7422)                       │
   │  └── Let's Encrypt ACME (Automatic TLS)                    │
   │                                                             │
   │ NetBird Services                                            │
   │  ├── NetBird Management + Signal + STUN (netbird-server)    │
   │  ├── NetBird Web Dashboard (dashboard)                     │
   │  └── NetBird Reverse Proxy (proxy, TCP passthrough)         │
   │                                                             │
   │ CrowdSec Intrusion Prevention System                        │
   │  ├── Real-time AppSec WAF inspecting HTTP/API requests      │
   │  └── Community Blocklists & Automated Bouncing             │
   └─────────────────────────────────────────────────────────────┘
```

---

## Generic Placeholders & How to Replace Them

This repository uses generic placeholders throughout the documentation, configuration templates, and deploy scripts. When preparing your deployment, replace these placeholders with your actual server and domain values:

| Generic Placeholder | Description | Example Real-World Value | Where It Is Used |
| :--- | :--- | :--- | :--- |
| `yourdomain.com` | Your primary root domain | `example.org`, `mycompany.io` | Domain registrar, DNS zone |
| `netbird.yourdomain.com` | Subdomain allocated for NetBird | `vpn.example.org`, `netbird.mycompany.io` | `NETBIRD_DOMAIN`, DNS record |
| `admin@yourdomain.com` | Administrator email for ACME TLS certificate registration | `noc@example.org`, `devops@mycompany.io` | `LETSENCRYPT_EMAIL`, Let's Encrypt notifications |
| `203.0.113.10` | Public IPv4 address of your VPS / Host server *(RFC 5737 placeholder)* | `198.51.100.42` | DNS **A** record target in your DNS provider |
| `39422` | Custom SSH port configured during OS bootstrap | Any custom port between `1024` and `65535` | `SSH_PORT` environment variable |
| `deploy` | Dedicated non-root user created for running services | Any standard username (e.g. `ubuntu`, `admin`) | `DEPLOY_USER` in `bootstrap-os.sh` |

---

## Supported Operating Systems & Required Binaries

`deploy.sh` is distro-agnostic and will run on **any modern Linux distribution** (Ubuntu, Debian, Fedora, Arch, Rocky, Alpine, etc.) provided the following CLI binaries are available in your `$PATH`:

| Binary | Minimum / Tested Version | Purpose in Stack | How to Install (Examples) |
| :--- | :--- | :--- | :--- |
| **`docker`** | `24.0+` (with Compose v2 plugin) | Container runtime and stack orchestration | Official Docker repo or distro package manager |
| **`openssl`** | `1.1.1` or `3.x` | Generates cryptographic encryption keys & bouncer API secrets | `apt install openssl` / `dnf install openssl` / `pacman -S openssl` |
| **`bash`** | `4.0+` | Script execution environment (`set -euo pipefail`) | Standard shell (`/bin/bash`) |
| **`sed`** | GNU `sed` or standard BSD | Instantiates runtime templates from `.example` files | Pre-installed on almost all distros |
| **`curl`** or **`dig`** | Any | DNS verification and endpoint health checks | `apt install dnsutils curl` / `dnf install bind-utils curl` |

### Distribution Support Level:
* **Ubuntu & Debian:** Running `./bootstrap-os.sh` automates the entire OS setup (Docker, UFW firewall, Fail2ban with aggressive SSH jail).
* **Fedora, RHEL, Rocky, AlmaLinux, Arch, openSUSE:**
  1. Install `docker` and `openssl` via your native package manager (`dnf`, `pacman`, `zypper`).
  2. Fail2ban will automatically use your native firewall (e.g. `firewallcmd-rich-rules` on RHEL/Fedora or `nftables` on Arch).
  3. Allow NetBird's required ports in your native firewall (e.g., for `firewalld`):
     ```bash
     sudo firewall-cmd --permanent --add-port=39422/tcp  # Your custom SSH port
     sudo firewall-cmd --permanent --add-port=80/tcp     # ACME / HTTP
     sudo firewall-cmd --permanent --add-port=443/tcp    # HTTPS / Websecure
     sudo firewall-cmd --permanent --add-port=443/udp    # HTTP/3 / QUIC
     sudo firewall-cmd --permanent --add-port=3478/udp   # STUN/TURN
     sudo firewall-cmd --permanent --add-port=51820/udp  # WireGuard relay
     sudo firewall-cmd --reload
     ```
  4. Run `./deploy.sh` directly.

---

## Step-by-Step Deployment Guide

### Step 1: DNS Setup

Before deploying, create an **A record** in your domain registrar or DNS management dashboard (e.g., Cloudflare, Porkbun, Namecheap, Route 53, Hetzner, etc.):

| Setting | Value to Enter | Explanation |
| :--- | :--- | :--- |
| **Record Type** | `A` | Maps your hostname to your server's public IPv4 |
| **Host / Name** | `netbird` *(or `@` if using root domain)* | Resolves `netbird.yourdomain.com` |
| **Value / Target** | `203.0.113.10` | **Replace with your VPS public IPv4** |
| **TTL** | `Auto` or `300` (5 minutes) | Caching duration |
| **Proxy Status** *(Cloudflare only)* | **DNS only (Grey Cloud) ☁️** | **CRITICAL: Must NOT be proxied (Orange Cloud)** |

> [!WARNING]
> **If using Cloudflare:** You **MUST set the record to "DNS only" (Grey cloud)**!
> NetBird relies on direct UDP ports (WireGuard `51820/udp`, STUN `3478/udp`) and long-lived gRPC streaming connections. Cloudflare's standard CDN/proxy will block raw UDP and disconnect your NetBird agents.

Verify that DNS has propagated from your local terminal:
```bash
dig +short netbird.yourdomain.com
# Should return your VPS IPv4 address!
```

---

### Step 2: Base OS Setup & Hardening (Run as root)

Run the included idempotent bootstrap script to harden SSH, configure Fail2ban, setup UFW firewall rules, and install Docker Engine with Compose:

```bash
# Optional: customize SSH port (default is 39422)
export SSH_PORT=39422
sudo bash bootstrap-os.sh
```

**What this does:**
1. Installs essential packages (`curl`, `ufw`, `fail2ban`, `htop`, `openssl`, etc.).
2. Creates a dedicated `deploy` user with passwordless `sudo` privileges and installs SSH authorized keys.
3. Hardens SSH on the chosen custom port, disabling root password login and keyboard-interactive authentication.
4. Sets up Fail2ban with an aggressive SSH jail linked to UFW.
5. Configures UFW firewall to allow only required ports (`SSH`, `80/tcp`, `443/tcp`, `443/udp`, `3478/udp`, `51820/udp`).
6. Installs upstream Docker Engine and the Docker Compose plugin.
7. Configures Docker daemon log rotation to prevent disk exhaustion.

---

### Step 3: Deploy NetBird Stack

Clone this repository to your target deployment directory (e.g. `/opt/netbird` or `/home/deploy/netbird`) and run `deploy.sh`:

```bash
# Specify your NetBird domain and Let's Encrypt email:
export NETBIRD_DOMAIN="netbird.yourdomain.com"
export LETSENCRYPT_EMAIL="admin@yourdomain.com"

./deploy.sh
```

*Alternatively, pass variables inline:*
```bash
NETBIRD_DOMAIN="netbird.yourdomain.com" LETSENCRYPT_EMAIL="admin@yourdomain.com" ./deploy.sh
```

**What happens automatically:**
* `.env` is created with a freshly generated `CROWDSEC_DASHBOARD_BOUNCER_KEY`.
* `dashboard.env` & `proxy.env` are generated from `.example` templates and populated with your domain.
* `config.yaml` is generated with cryptographic `authSecret` and `encryptionKey` values.
* Docker Compose brings up Traefik, NetBird Server, NetBird Dashboard, NetBird Proxy, and CrowdSec.
* Traefik provisions SSL certificates via Let's Encrypt.
* CrowdSec loads AppSec WAF rules on port `7422` and streams decisions to Traefik.

---

## Safe In-Place Updates (Zero Secret Overwrites)

When updating an existing deployment (e.g. pulling new repository commits):

```bash
cd /opt/netbird
git pull
./deploy.sh
```

### Safety Guarantees:
* **No domain prompt needed:** The script automatically detects the active domain from your existing configuration.
* **Zero secret overwrites:** Existing `.env`, `dashboard.env`, `proxy.env`, `config.yaml`, and tokens are **preserved untouched**.
* **Zero database wipes:** Docker volumes (`netbird_data`, `netbird_traefik_letsencrypt`, `crowdsec_db`) persist across updates.
* **Minimal downtime:** Docker Compose only recreates containers whose image or configuration has changed.

---

## Updating CrowdSec Security Rules & AppSec WAF

CrowdSec IP blocklists, community threat intelligence, and AppSec WAF virtual patches update continuously without needing Docker container rebuilds:

```bash
./deploy.sh --update-rules
```
*(This triggers `cscli hub update && cscli hub upgrade` inside the CrowdSec container with 0 downtime).*

---

## Disaster Recovery & Database Backup / Restore

If your VPS was lost and you are rebuilding on a fresh VPS, you can restore all your **existing connected peers, WireGuard keys, and user accounts**:

### Step 1: Deploy with your original encryption key
```bash
export NETBIRD_DOMAIN="netbird.yourdomain.com"
export LETSENCRYPT_EMAIL="admin@yourdomain.com"
export NETBIRD_ENCRYPTION_KEY="<your-stored-base64-encryption-key-from-config.yaml>"

./deploy.sh
```

### Step 2: Restore the SQLite Database
1. Stop the management server:
   ```bash
   docker compose stop netbird-server
   ```
2. Locate the volume path:
   ```bash
   VOLUME_DIR="$(docker volume inspect $(docker compose ps -q netbird-server | xargs docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/netbird"}}{{.Name}}{{end}}{{end}}') -f '{{.Mountpoint}}')"
   ```
3. Copy your database backup files into the volume:
   ```bash
   cp store.db idp.db "${VOLUME_DIR}/"
   chown -R root:root "${VOLUME_DIR}/"*.db
   ```
4. Restart the server:
   ```bash
   docker compose start netbird-server
   ```
All peers will immediately reconnect without needing re-pairing!

---

## Verification & Health Testing

Verify that your deployment is healthy and protected by CrowdSec AppSec:

```bash
# 1. Normal access returns 200 OK:
curl -ks -I https://netbird.yourdomain.com

# 2. Malicious probe returns 403 Forbidden (blocked by CrowdSec AppSec WAF):
curl -ks -I https://netbird.yourdomain.com/.env
curl -ks -I https://netbird.yourdomain.com/api/.env
```

Check AppSec metrics and registered bouncers inside CrowdSec:
```bash
docker exec netbird-crowdsec cscli metrics show appsec
docker exec netbird-crowdsec cscli alerts list
docker exec netbird-crowdsec cscli bouncers list
```

---

## Pinned Versions

All container images are pinned to tested, immutable versions to prevent unexpected breaking changes:
* **NetBird Dashboard:** `netbirdio/dashboard:v2.92.0`
* **NetBird Server:** `netbirdio/netbird-server:0.80.0`
* **NetBird Reverse Proxy:** `netbirdio/reverse-proxy:0.80.0`
* **Traefik Proxy:** `traefik:v3.6`
* **CrowdSec:** `crowdsecurity/crowdsec:v1.8.1`

---

## License

This project is licensed under the [MIT License](LICENSE).
