#!/usr/bin/env bash
set -euo pipefail
set -o errtrace
trap 'echo "ERROR: command failed at line $LINENO"; exit 1' ERR

# --- Ubuntu-only check ---
if [ ! -f /etc/os-release ]; then
    echo "This script only supports Ubuntu."
    exit 1
fi

. /etc/os-release
if [ "${ID,,}" != "ubuntu" ]; then
    echo "This script only supports Ubuntu. Detected: ${ID}"
    exit 1
fi

echo "Detected Ubuntu ${VERSION_CODENAME:-unknown}"
echo "Starting NGINX installation..."

# --- Step 1: Install prerequisites ---
sudo apt update -y
sudo apt install -y curl gnupg2 ca-certificates lsb-release ubuntu-keyring

# --- Step 2: Import NGINX signing key ---
echo "Importing NGINX GPG key..."
curl -fsSL https://nginx.org/keys/nginx_signing.key \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

# --- Step 3: Verify GPG fingerprint ---
echo "Verifying NGINX GPG key fingerprint..."

VALID_FPS=(
  "573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62" # legacy
  "8540A6F18833A80E9C1653A42FD21310B49F6B46" # new (current)
  "9E9BE90EACBCDE69FE9B204CBCDCD8A38D88A2B3" # additional
)

FOUND_FPS=$(gpg --dry-run --quiet --no-keyring \
  --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg \
  | grep -Eo '[0-9A-F]{40}' | sort -u || true)

match=""
for fp in ${FOUND_FPS}; do
  for v in "${VALID_FPS[@]}"; do
    if [ "$fp" = "$v" ]; then
      match="$fp"
      break
    fi
  done
done

if [ -z "$match" ]; then
  echo "ERROR: Invalid or unknown NGINX signing key fingerprint!"
  echo "Found: ${FOUND_FPS:-none}"
  echo "Expected one of: ${VALID_FPS[*]}"
  exit 1
else
  echo "GPG key verified. Matched fingerprint: $match"
fi

# --- Step 4: Add NGINX APT repository (stable) ---
echo "Adding NGINX APT repository (stable)..."
echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] \
http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" \
  | sudo tee /etc/apt/sources.list.d/nginx.list >/dev/null

# --- Step 5: Pin nginx.org repo ---
echo "Setting APT pinning for nginx.org..."
printf "Package: *\nPin: origin nginx.org\nPin: release o=nginx\nPin-Priority: 900\n" \
  | sudo tee /etc/apt/preferences.d/99nginx >/dev/null

# --- Step 6: Install NGINX ---
echo "Installing NGINX..."
sudo apt update -y
sudo apt install -y nginx

# --- Step 7: Enable, start and restart service ---
echo "Enabling NGINX service..."
sudo systemctl enable nginx

echo "Starting NGINX service..."
sudo systemctl start nginx

echo "Restarting NGINX service..."
sudo systemctl restart nginx

# --- Step 8: Verify status & version ---
echo
echo "NGINX installed and running successfully!"
echo "Version:"
nginx -v 2>&1
echo
echo "Service status:"
sudo systemctl --no-pager --full status nginx | head -n 10
echo
echo "Installation complete. NGINX is ready."