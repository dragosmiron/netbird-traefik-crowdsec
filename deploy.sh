#!/usr/bin/env bash
set -euo pipefail

# NetBird Stack Deployment Script
# Supports:
#   1. Running from scratch on a blank VPS (requires NETBIRD_DOMAIN)
#   2. Running on an existing VPS (safely detects domain and updates containers without overwriting)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Dedicated option to update CrowdSec threat intelligence & AppSec virtual patches
if [[ "${1:-}" == "--update-rules" ]] || [[ "${1:-}" == "--update-security" ]]; then
  echo "==> [NetBird] Updating CrowdSec Hub rules & AppSec virtual patches..."
  docker compose exec -T crowdsec cscli hub update
  docker compose exec -T crowdsec cscli hub upgrade
  docker compose exec -T crowdsec cscli reload
  echo "==> [NetBird] CrowdSec security rules updated successfully."
  exit 0
fi

echo "==> [NetBird] Checking environment & dependencies..."

# Ensure required CLI utilities are installed
if ! command -v openssl &>/dev/null; then
  echo "    --> Installing missing dependency: openssl..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -y && sudo apt-get install -y openssl
  elif command -v yum &>/dev/null; then
    sudo yum install -y openssl
  else
    echo "    [ERROR] 'openssl' is required to generate cryptographic secrets but could not be installed." >&2
    exit 1
  fi
fi

if ! command -v docker &>/dev/null; then
  echo "    [ERROR] 'docker' is not installed! Please run ./bootstrap-os.sh first." >&2
  exit 1
fi

# 1. Detect domain if already configured on an existing deployment
EXISTING_DOMAIN=""
EXISTING_EMAIL=""
if [[ -f .env ]]; then
  if grep -q "^NETBIRD_DOMAIN=" .env; then
    EXISTING_DOMAIN="$(grep "^NETBIRD_DOMAIN=" .env | cut -d "=" -f2- | tr -d " \"'" )"
  fi
  if grep -q "^LETSENCRYPT_EMAIL=" .env; then
    EXISTING_EMAIL="$(grep "^LETSENCRYPT_EMAIL=" .env | cut -d "=" -f2- | tr -d " \"'" )"
  fi
fi

if [[ -z "${EXISTING_DOMAIN}" ]] && [[ -f dashboard.env ]] && grep -q "^NETBIRD_MGMT_API_ENDPOINT=" dashboard.env; then
  EXISTING_DOMAIN="$(grep "^NETBIRD_MGMT_API_ENDPOINT=" dashboard.env | cut -d "=" -f2- | sed -e "s|https://||" -e "s|http://||" -e "s|/.*||" | tr -d " \"'" )"
fi

if [[ -z "${EXISTING_EMAIL}" ]] && [[ -f docker-compose.yml ]] && grep -q "certificatesresolvers.letsencrypt.acme.email=" docker-compose.yml; then
  EXISTING_EMAIL="$(grep -o "certificatesresolvers.letsencrypt.acme.email=[^ \"'\''}]*" docker-compose.yml | head -n1 | cut -d "=" -f2 | tr -d " \"'")"
fi

# 2. Determine active domain (CLI variable takes precedence, otherwise existing deployment)
DOMAIN="${NETBIRD_DOMAIN:-${EXISTING_DOMAIN}}"
LE_EMAIL="${LETSENCRYPT_EMAIL:-${EXISTING_EMAIL}}"

# 3. If no domain is configured and none was provided, FAIL WITH HOW-TO GUIDE
if [[ -z "${DOMAIN}" ]]; then
  echo "" >&2
  echo "================================================================================" >&2
  echo " [ERROR] NETBIRD_DOMAIN is not set!" >&2
  echo "================================================================================" >&2
  echo " No existing NetBird deployment was detected in this directory." >&2
  echo "" >&2
  echo " To deploy NetBird from scratch, specify your domain (and optional Let's Encrypt email):" >&2
  echo "" >&2
  echo "   export NETBIRD_DOMAIN=\"netbird.yourdomain.com\"" >&2
  echo "   export LETSENCRYPT_EMAIL=\"admin@yourdomain.com\"" >&2
  echo "   ./deploy.sh" >&2
  echo "" >&2
  echo " Or pass inline:" >&2
  echo "   NETBIRD_DOMAIN=\"netbird.yourdomain.com\" LETSENCRYPT_EMAIL=\"admin@yourdomain.com\" ./deploy.sh" >&2
  echo "" >&2
  echo " See README.md for the complete step-by-step guide." >&2
  echo "================================================================================" >&2
  exit 1
fi

if [[ -z "${LE_EMAIL}" ]]; then
  LE_EMAIL="admin@${DOMAIN}"
fi

FORCE="${FORCE:-false}"

echo ""
echo "================================================================================"
echo " ==> Deployment Configuration Summary"
echo " Target Domain:       ${DOMAIN}"
echo " Let's Encrypt Email: ${LE_EMAIL}"
echo " Deployment Type:     $([[ -n "${EXISTING_DOMAIN}" ]] && echo 'Existing In-Place Update' || echo 'Fresh Installation')"
echo "================================================================================"
echo " To customize these values (e.g. NETBIRD_DOMAIN, LETSENCRYPT_EMAIL), see README.md."
echo " Press Ctrl+C or answer 'n' to abort and adjust your environment variables."
echo "================================================================================"

if [[ "${FORCE}" != "true" ]] && [[ -t 0 ]]; then
  read -r -p "Proceed with these settings? [y/N]: " confirm
  if [[ "${confirm}" != [yY] && "${confirm}" != [yY][eE][sS] ]]; then
    echo "Aborted by user. No changes were made."
    exit 1
  fi
fi

# 4. Generate or update .env
if [[ ! -f .env ]]; then
  echo "    --> Creating .env with auto-generated CrowdSec Bouncer keys..."
  BOUNCER_KEY="$(openssl rand -hex 32)"
  PROXY_BOUNCER_KEY="$(openssl rand -hex 32)"
  cat > .env << EOF
NETBIRD_DOMAIN=${DOMAIN}
LETSENCRYPT_EMAIL=${LE_EMAIL}
CROWDSEC_DASHBOARD_BOUNCER_KEY=${BOUNCER_KEY}
CROWDSEC_PROXY_BOUNCER_KEY=${PROXY_BOUNCER_KEY}
EOF
  chmod 600 .env
else
  # Update/append domain, email, and bouncer keys if missing from an existing .env
  if ! grep -q "^NETBIRD_DOMAIN=" .env; then
    echo "NETBIRD_DOMAIN=${DOMAIN}" >> .env
  fi
  if ! grep -q "^LETSENCRYPT_EMAIL=" .env; then
    echo "LETSENCRYPT_EMAIL=${LE_EMAIL}" >> .env
  fi
  if ! grep -q "^CROWDSEC_DASHBOARD_BOUNCER_KEY=" .env; then
    echo "CROWDSEC_DASHBOARD_BOUNCER_KEY=$(openssl rand -hex 32)" >> .env
  fi
  if ! grep -q "^CROWDSEC_PROXY_BOUNCER_KEY=" .env; then
    echo "CROWDSEC_PROXY_BOUNCER_KEY=$(openssl rand -hex 32)" >> .env
  fi
fi

# 5. Generate dashboard.env if missing
if [[ ! -f dashboard.env ]]; then
  if [[ -f configs/dashboard.env.example ]]; then
    echo "    --> Creating dashboard.env for domain: ${DOMAIN}..."
    sed "s|netbird\.example\.com|${DOMAIN}|g" configs/dashboard.env.example > dashboard.env
    chmod 600 dashboard.env
  else
    echo "    [WARN] dashboard.env missing and configs/dashboard.env.example not found." >&2
  fi
fi

# 6. Generate proxy.env if missing
if [[ ! -f proxy.env ]]; then
  if [[ -f configs/proxy.env.example ]]; then
    echo "    --> Creating proxy.env for domain: ${DOMAIN}..."
    PROXY_KEY="$(grep "^CROWDSEC_PROXY_BOUNCER_KEY=" .env | cut -d "=" -f2- | tr -d " \"'" || openssl rand -hex 32)"
    sed -e "s|netbird\.example\.com|${DOMAIN}|g" \
        -e "s|GENERATE_WITH_CSCLI_BOUNCERS_ADD|${PROXY_KEY}|g" \
        configs/proxy.env.example > proxy.env
    chmod 600 proxy.env
  else
    echo "    [WARN] proxy.env missing and configs/proxy.env.example not found." >&2
  fi
fi

# 7. Generate config.yaml if missing
if [[ ! -f config.yaml ]]; then
  if [[ -f configs/config.yaml.example ]]; then
    echo "    --> Creating config.yaml with secure cryptographic keys..."
    AUTH_SECRET="$(openssl rand -base64 32)"
    ENC_KEY="${NETBIRD_ENCRYPTION_KEY:-$(openssl rand -base64 32)}"
    
    sed -e "s|netbird\.example\.com|${DOMAIN}|g" \
        -e "s|authSecret: \"GENERATE_RANDOM_BASE64_32_CHARS\"|authSecret: \"${AUTH_SECRET}\"|g" \
        -e "s|encryptionKey: \"GENERATE_RANDOM_BASE64_32_CHARS\"|encryptionKey: \"${ENC_KEY}\"|g" \
        configs/config.yaml.example > config.yaml
    chmod 600 config.yaml
  else
    echo "    [WARN] config.yaml missing and configs/config.yaml.example not found." >&2
  fi
fi

echo "==> [NetBird] Validating Docker Compose syntax..."
docker compose config --quiet

echo "==> [NetBird] Applying services..."
docker compose up -d

echo "==> [NetBird] Waiting for CrowdSec healthcheck..."
for i in {1..30}; do
  if docker compose exec -T crowdsec cscli lapi status >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "==> [NetBird] Status:"
docker compose ps

echo "==> [NetBird] Deployment finished successfully."
