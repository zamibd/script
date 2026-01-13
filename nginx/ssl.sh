#!/usr/bin/env bash
set -euo pipefail

# Re-run as root if needed
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "[i] Root privileges required — re-running with sudo..."
  exec sudo -E bash "$0" "$@"
fi

hr() { printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '-'; }
ok() { echo -e "✅ $*"; }
info() { echo -e "ℹ️  $*"; }
err() { echo -e "❌ $*" >&2; }

trap 'err "An error occurred. Check the logs above."; exit 1' ERR

# Ubuntu check
[ -f /etc/os-release ] || { err "This script only supports Ubuntu."; exit 1; }
. /etc/os-release
[ "${ID,,}" = "ubuntu" ] || { err "This script only supports Ubuntu."; exit 1; }

hr
echo "Let's Encrypt Wildcard (Cloudflare DNS) setup starting..."
hr

# Install deps
info "Installing Certbot + Cloudflare plugin..."
apt update -y
apt install -y certbot python3-certbot-dns-cloudflare
ok "Packages installed."

# Inputs
echo
read -rp "Enter your domain (e.g., example.com): " DOMAIN
DOMAIN="${DOMAIN,,}"
[ -n "$DOMAIN" ] || { err "Domain cannot be empty."; exit 1; }

read -rp "Enter your email for Let's Encrypt notifications: " EMAIL
[ -n "$EMAIL" ] || { err "Email cannot be empty."; exit 1; }

read -rp "Enter your Cloudflare API Token: " CF_TOKEN
[ -n "$CF_TOKEN" ] || { err "API Token cannot be empty."; exit 1; }

# Create Cloudflare credentials file
CF_INI="/root/.secrets/cloudflare.ini"
mkdir -p /root/.secrets
cat > "$CF_INI" <<EOF
dns_cloudflare_api_token = $CF_TOKEN
EOF
chmod 600 "$CF_INI"

hr
echo "Requesting Wildcard SSL certificate for *.${DOMAIN} ..."
hr

certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials "$CF_INI" \
  -d "$DOMAIN" \
  -d "*.$DOMAIN" \
  --agree-tos -m "$EMAIL" \
  --no-eff-email \
  --non-interactive

ok "Wildcard SSL issued for ${DOMAIN} and *.${DOMAIN}"

# Enable auto-renew
info "Enabling auto-renewal..."
systemctl enable --now certbot.timer 2>/dev/null || true
ok "Auto-renewal enabled."

# Test
info "Testing renewal (dry-run)..."
certbot renew --dry-run
ok "Dry-run successful."

hr
echo "🎉 Wildcard SSL ready!"
echo
echo "Paths:"
echo "  /etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
echo "  /etc/letsencrypt/live/${DOMAIN}/privkey.pem"
hr
