#!/usr/bin/env bash
set -euo pipefail
set -o errtrace
trap 'echo "ERROR: command failed at line $LINENO"; exit 1' ERR

# -------- Ubuntu-only guard --------
[ -f /etc/os-release ] || { echo "This script only supports Ubuntu."; exit 1; }
. /etc/os-release
[ "${ID,,}" = "ubuntu" ] || { echo "This script only supports Ubuntu. Detected: ${ID}"; exit 1; }

# -------- Prompt for Domain and Email --------
read -r -p "Enter your domain (e.g., imzami.com): " DOMAIN
read -r -p "Enter your email for Let's Encrypt notifications: " EMAIL

# Basic validation
if [ -z "$DOMAIN" ]; then
  echo "Domain is required."; exit 1;
fi
if [ -z "$EMAIL" ]; then
  echo "Email is required."; exit 1;
fi

# Variables
WWWROOT_BASE="/var/www"
NGINX_CONF_DIR="/etc/nginx/conf.d"
PRIMARY_DOMAIN="$DOMAIN"
WEBROOT="${WWWROOT_BASE}/${PRIMARY_DOMAIN}"
SERVER_BLOCK="${NGINX_CONF_DIR}/${PRIMARY_DOMAIN}.conf"

echo
echo "=== Configuration ==="
echo "Domain      : $PRIMARY_DOMAIN"
echo "Email       : $EMAIL"
echo "Webroot     : $WEBROOT"
echo "Nginx conf  : $SERVER_BLOCK"
echo

# -------- Install dependencies --------
echo "Installing prerequisites..."
sudo apt update -y
sudo apt install -y nginx curl ca-certificates lsb-release software-properties-common
sudo apt install -y certbot python3-certbot-nginx

# -------- Enable & start nginx --------
sudo systemctl enable nginx
sudo systemctl start nginx

# -------- Create webroot and basic config --------
echo "Setting up NGINX server block..."
sudo mkdir -p "$WEBROOT"
sudo chown -R "$USER":"$USER" "$WEBROOT" || true
if [ ! -f "${WEBROOT}/index.html" ]; then
  cat <<HTML | sudo tee "${WEBROOT}/index.html" >/dev/null
<!doctype html><title>${PRIMARY_DOMAIN}</title><h1>${PRIMARY_DOMAIN} - SSL Setup</h1>
HTML
fi

sudo tee "$SERVER_BLOCK" >/dev/null <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${PRIMARY_DOMAIN};
    root ${WEBROOT};
    index index.html;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
NGINX

echo "Validating NGINX config..."
sudo nginx -t
sudo systemctl reload nginx

# -------- Obtain SSL via Certbot --------
echo "Requesting Let's Encrypt SSL certificate for ${PRIMARY_DOMAIN}..."
sudo certbot --nginx -d "$PRIMARY_DOMAIN" \
  -m "$EMAIL" --agree-tos --no-eff-email --redirect

# -------- Enable auto-renewal --------
echo "Enabling automatic SSL renewal..."
if systemctl list-unit-files | grep -q '^certbot.timer'; then
  sudo systemctl enable --now certbot.timer
else
  if ! sudo crontab -l 2>/dev/null | grep -q 'certbot renew'; then
    (sudo crontab -l 2>/dev/null; echo '0 3 * * * certbot renew --quiet --deploy-hook "systemctl reload nginx"') | sudo crontab -
  fi
fi

# -------- Verify & finish --------
echo
echo "SSL certificate details:"
sudo certbot certificates | grep -A3 "Domains:" || true

echo
echo "Reloading NGINX..."
sudo nginx -t
sudo systemctl reload nginx

echo
echo "✅ SUCCESS: SSL is fully configured and active!"
echo "Domain        : $PRIMARY_DOMAIN"
echo "Email         : $EMAIL"
echo "Webroot       : $WEBROOT"
echo "Nginx conf    : $SERVER_BLOCK"
echo "Auto-renewal  : enabled"
