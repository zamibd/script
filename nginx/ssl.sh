#!/usr/bin/env bash
set -euo pipefail
set -o errtrace
trap 'echo "ERROR: command failed at line $LINENO"; exit 1' ERR

# --------------- Ubuntu-only guard ---------------
[ -f /etc/os-release ] || { echo "This script only supports Ubuntu."; exit 1; }
. /etc/os-release
[ "${ID,,}" = "ubuntu" ] || { echo "This script only supports Ubuntu. Detected: ${ID}"; exit 1; }

# --------------- Helpers ---------------
prompt() {
  # usage: prompt "Question" "default" varname
  local q="${1:-}" def="${2:-}" varname="${3:-}"
  local ans
  if [ -n "$def" ]; then
    read -r -p "$q [$def]: " ans || true
    ans="${ans:-$def}"
  else
    read -r -p "$q: " ans || true
  fi
  printf -v "$varname" '%s' "$ans"
}

prompt_yn() {
  # usage: prompt_yn "Question (y/n)" default_y|default_n varname
  local q="${1:-}" def="${2:-default_y}" varname="${3:-}"
  local hint="Y/n"
  local defval="y"
  if [ "$def" = "default_n" ]; then
    hint="y/N"
    defval="n"
  fi
  local ans
  read -r -p "$q [$hint]: " ans || true
  ans="${ans:-$defval}"
  case "${ans,,}" in
    y|yes) printf -v "$varname" '%s' "y" ;;
    n|no)  printf -v "$varname" '%s' "n" ;;
    *)     printf -v "$varname" '%s' "$defval" ;;
  esac
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1"; exit 1; }
}

validate_email() {
  local e="$1"
  [[ "$e" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

# --------------- Collect input (args/env or interactive) ---------------
DOMAIN="${DOMAIN:-${1:-}}"
EMAIL="${EMAIL:-${2:-}}"
EXTRA_DOMAINS="${EXTRA_DOMAINS:-}"   # comma-separated
AUTO_REDIRECT="${AUTO_REDIRECT:-}"    # y/n
STAGING="${STAGING:-}"                # y/n
WWWROOT_BASE="${WWWROOT_BASE:-/var/www}"
NGINX_CONF_DIR="${NGINX_CONF_DIR:-/etc/nginx/conf.d}"

if [ -z "${DOMAIN}" ]; then
  prompt "Enter primary domain (e.g., example.com)" "" DOMAIN
fi

if [ -z "${EMAIL}" ]; then
  prompt "Enter email for Let's Encrypt notifications" "" EMAIL
fi

if [ -z "${EXTRA_DOMAINS}" ]; then
  prompt_yn "Also include www subdomain?" default_y ADD_WWW
  if [ "$ADD_WWW" = "y" ]; then
    EXTRA_DOMAINS="www.${DOMAIN}"
  fi
  prompt_yn "Add more domains (SAN) now?" default_n ADD_MORE
  if [ "$ADD_MORE" = "y" ]; then
    read -r -p "Enter additional domains (comma-separated, excluding primary): " EXTRA_INPUT || true
    if [ -n "${EXTRA_INPUT:-}" ]; then
      if [ -n "$EXTRA_DOMAINS" ]; then
        EXTRA_DOMAINS="$EXTRA_DOMAINS,$EXTRA_INPUT"
      else
        EXTRA_DOMAINS="$EXTRA_INPUT"
      fi
    fi
  fi
fi

if [ -z "${AUTO_REDIRECT}" ]; then
  prompt_yn "Force HTTP -> HTTPS redirect?" default_y AUTO_REDIRECT
fi

if [ -z "${STAGING}" ]; then
  prompt_yn "Use Let's Encrypt STAGING (testing, not trusted)?" default_n STAGING
fi

# Basic validations
[ -n "$DOMAIN" ] || { echo "Domain is required."; exit 2; }
[ -n "$EMAIL" ]  || { echo "Email is required."; exit 2; }
validate_email "$EMAIL" || { echo "Invalid email format: $EMAIL"; exit 2; }

PRIMARY_DOMAIN="$DOMAIN"
ALL_DOMAINS="$PRIMARY_DOMAIN"
if [ -n "$EXTRA_DOMAINS" ]; then
  # normalize commas/spaces
  EXTRA_DOMAINS="$(echo "$EXTRA_DOMAINS" | tr -s ' ' | tr ' ' ',' | sed 's/,,*/,/g' | sed 's/^,*//; s/,*$//')"
  [ -n "$EXTRA_DOMAINS" ] && ALL_DOMAINS="$ALL_DOMAINS,$EXTRA_DOMAINS"
fi

echo
echo "=== Plan Summary ==="
echo "Primary domain    : $PRIMARY_DOMAIN"
echo "Extra domains     : ${EXTRA_DOMAINS:-none}"
echo "Email             : $EMAIL"
echo "Redirect HTTP->HTTPS: $([ "${AUTO_REDIRECT,,}" = "y" ] && echo enabled || echo disabled)"
echo "Let's Encrypt env : $([ "${STAGING,,}" = "y" ] && echo STAGING/test || echo PRODUCTION)"
echo "Webroot base      : $WWWROOT_BASE"
echo "Nginx conf dir    : $NGINX_CONF_DIR"
echo

prompt_yn "Proceed?" default_y OKGO
[ "$OKGO" = "y" ] || { echo "Aborted by user."; exit 0; }

# --------------- Install prerequisites ---------------
echo "Installing prerequisites..."
sudo apt update -y
sudo apt install -y nginx curl ca-certificates lsb-release software-properties-common
sudo apt install -y certbot python3-certbot-nginx

# Ensure required commands
require_cmd nginx
require_cmd certbot

# Ensure NGINX is running
sudo systemctl enable nginx
sudo systemctl start nginx

# --------------- Minimal server block (if missing) ---------------
WEBROOT="${WWWROOT_BASE}/${PRIMARY_DOMAIN}"
SERVER_BLOCK="${NGINX_CONF_DIR}/${PRIMARY_DOMAIN}.conf"

if ! grep -Rqs "server_name .*${PRIMARY_DOMAIN}" /etc/nginx; then
  echo "Creating minimal NGINX server block for ${PRIMARY_DOMAIN}..."
  sudo mkdir -p "$WEBROOT"
  sudo chown -R "$USER":"$USER" "$WEBROOT" || true
  if [ ! -f "${WEBROOT}/index.html" ]; then
    cat <<HTML | sudo tee "${WEBROOT}/index.html" >/dev/null
<!doctype html><title>${PRIMARY_DOMAIN}</title><h1>${PRIMARY_DOMAIN}</h1>
HTML
  fi

  sudo tee "$SERVER_BLOCK" >/dev/null <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name ${ALL_DOMAINS//,/ };
    root ${WEBROOT};
    location / { try_files \$uri \$uri/ =404; }
}
NGINX
fi

echo "Validating NGINX config..."
sudo nginx -t
sudo systemctl reload nginx

# --------------- Request certificate ---------------
CERTBOT_FLAGS=(--nginx -d "$PRIMARY_DOMAIN" -m "$EMAIL" --agree-tos --no-eff-email)

IFS=',' read -r -a doms <<< "$ALL_DOMAINS"
for d in "${doms[@]}"; do
  if [ "$d" != "$PRIMARY_DOMAIN" ]; then
    CERTBOT_FLAGS+=(-d "$d")
  fi
done

if [ "${AUTO_REDIRECT,,}" = "y" ]; then
  CERTBOT_FLAGS+=(--redirect)
fi

if [ "${STAGING,,}" = "y" ]; then
  echo "Using Let's Encrypt STAGING (test certificates)."
  CERTBOT_FLAGS+=(--test-cert)
fi

echo "Running Certbot..."
sudo certbot "${CERTBOT_FLAGS[@]}"

# --------------- Enable auto-renewal ---------------
echo "Enabling auto-renewal..."
if systemctl list-unit-files | grep -q '^certbot.timer'; then
  sudo systemctl enable --now certbot.timer
else
  if ! sudo crontab -l 2>/dev/null | grep -q 'certbot renew'; then
    (sudo crontab -l 2>/dev/null; echo '0 3 * * * certbot renew --quiet --deploy-hook "systemctl reload nginx"') | sudo crontab -
  fi
fi

# --------------- Final checks ---------------
echo
echo "Certificate summary:"
sudo certbot certificates | sed -n '1,200p' || true

echo
echo "Reloading NGINX..."
sudo nginx -t
sudo systemctl reload nginx

echo
echo "SUCCESS: SSL is configured."
echo "Domains        : $ALL_DOMAINS"
echo "Webroot        : $WEBROOT"
echo "NGINX conf     : $SERVER_BLOCK"
echo "Redirect       : $([ "${AUTO_REDIRECT,,}" = "y" ] && echo enabled || echo disabled)"
echo "Auto-renewal   : enabled"