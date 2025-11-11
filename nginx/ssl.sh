#!/usr/bin/env bash
set -euo pipefail

# Re-run as root if needed
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  echo "[i] Root privileges required — re-running with sudo..."
  exec sudo -E bash "$0" "$@"
fi

# Pretty log helpers
hr() { printf '%*s\n' "${COLUMNS:-80}" '' | tr ' ' '-'; }
ok() { echo -e "✅ $*"; }
info() { echo -e "ℹ️  $*"; }
err() { echo -e "❌ $*" >&2; }

trap 'err "An error occurred. Check the logs above."; exit 1' ERR

hr
echo "Let's Encrypt (Certbot standalone) setup starting..."
hr

# -------- Ubuntu-only check --------
[ -f /etc/os-release ] || { err "This script only supports Ubuntu."; exit 1; }
. /etc/os-release
[ "${ID,,}" = "ubuntu" ] || { err "This script only supports Ubuntu (detected: ${ID})."; exit 1; }

# 1) Update & install dependencies
info "Updating package lists..."
apt update -y
apt install -y certbot
ok "Certbot installed successfully."

# 2) Prompt for domain and email
echo
read -rp "Enter your domain (e.g., example.com): " DOMAIN
DOMAIN="${DOMAIN,,}"
if [[ -z "${DOMAIN}" ]]; then
  err "Domain cannot be empty."; exit 1
fi

read -rp "Enter your email for Let's Encrypt notifications: " EMAIL
if [[ -z "${EMAIL}" ]]; then
  err "Email cannot be empty."; exit 1
fi

hr
echo "Requesting Let's Encrypt SSL certificate (standalone mode)..."
hr

# 3) Stop anything using port 80 (optional, certbot will handle)
systemctl stop nginx 2>/dev/null || true
systemctl stop apache2 2>/dev/null || true

# 4) Request SSL certificate (HTTP-01 standalone)
certbot certonly --standalone \
  -d "${DOMAIN}" \
  --agree-tos -m "${EMAIL}" \
  --no-eff-email \
  --non-interactive

ok "SSL certificate issued successfully for ${DOMAIN}."

# 5) Enable auto-renewal
info "Enabling automatic SSL renewal..."
if systemctl list-unit-files | grep -q '^certbot.timer'; then
  systemctl enable --now certbot.timer
else
  if ! crontab -l 2>/dev/null | grep -q 'certbot renew'; then
    (crontab -l 2>/dev/null; echo '0 3 * * * certbot renew --quiet') | crontab -
  fi
fi
ok "Auto-renewal enabled."

# 6) Test dry-run renewal
info "Testing certificate renewal (dry-run)..."
certbot renew --dry-run
ok "Dry-run renewal succeeded."

# 7) Summary
hr
echo "🎉 SSL certificate for ${DOMAIN} has been installed successfully!"
echo
echo "Certificate files:"
echo "  /etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
echo "  /etc/letsencrypt/live/${DOMAIN}/privkey.pem"
echo
echo "You can use these paths in your web server config or Docker setup."
echo
echo "Verify expiry date:"
echo "  openssl x509 -in /etc/letsencrypt/live/${DOMAIN}/fullchain.pem -noout -dates"
hr
certbot --version
ok "Let's Encrypt standalone setup complete!"
