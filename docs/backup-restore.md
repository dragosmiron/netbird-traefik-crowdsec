# NetBird Backup & Disaster Recovery Guide

When rebuilding a server from scratch or migrating to a new VPS, follow this guide to restore all your existing NetBird connected peers, WireGuard encryption keys, and user accounts.

---

## 1. What Needs to be Backed Up?

Two items are required:
1. **Encryption Key**: The `encryptionKey` value from `config.yaml`.
2. **SQLite Database Files**: `store.db` and `idp.db` located inside the `netbird_data` Docker volume (`/var/lib/netbird`).

---

## 2. Backup Procedure

```bash
# 1. Stop management server to ensure clean database state:
docker compose stop netbird-server

# 2. Locate the volume mountpoint:
VOLUME_DIR="$(docker volume inspect $(docker compose ps -q netbird-server | xargs docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/netbird"}}{{.Name}}{{end}}{{end}}') -f '{{.Mountpoint}}')"

# 3. Create backup archive:
tar -czvf netbird-backup-$(date +%F).tar.gz -C "${VOLUME_DIR}" store.db idp.db

# 4. Restart server:
docker compose start netbird-server
```

Save the `.tar.gz` archive and your `encryptionKey` securely off-site.

---

## 3. Restore Procedure on a Fresh VPS

### Step 1: Deploy with Your Stored Encryption Key
```bash
export NETBIRD_DOMAIN="netbird.yourdomain.com"
export LETSENCRYPT_EMAIL="admin@yourdomain.com"
export NETBIRD_ENCRYPTION_KEY="<your-stored-base64-encryption-key>"

./deploy.sh
```

### Step 2: Restore Database Files
```bash
# 1. Stop management server:
docker compose stop netbird-server

# 2. Extract database files into the volume:
VOLUME_DIR="$(docker volume inspect $(docker compose ps -q netbird-server | xargs docker inspect -f '{{range .Mounts}}{{if eq .Destination "/var/lib/netbird"}}{{.Name}}{{end}}{{end}}') -f '{{.Mountpoint}}')"
tar -xzvf netbird-backup-YYYY-MM-DD.tar.gz -C "${VOLUME_DIR}/"
chown -R root:root "${VOLUME_DIR}/"*.db

# 3. Restart server:
docker compose start netbird-server
```

All peers will immediately reconnect without requiring re-pairing or new keys.
