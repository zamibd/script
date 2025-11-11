#!/usr/bin/env bash
set -euo pipefail
set -o errtrace
trap 'echo "ERROR: command failed at line $LINENO"; exit 1' ERR

# ----------------- Must run as root/sudo -----------------
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Please run this script with sudo or as root."
  exit 1
fi

# ----------------- Ubuntu-only guard -----------------
[ -f /etc/os-release ] || { echo "This script only supports Ubuntu."; exit 1; }
. /etc/os-release
if [ "${ID,,}" != "ubuntu" ]; then
  echo "This script only supports Ubuntu. Detected: ${ID}"
  exit 1
fi
echo "Detected Ubuntu ${VERSION_CODENAME:-unknown}"
echo "Starting Docker installation..."

# ----------------- Prerequisites -----------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https

# ----------------- Add Docker official GPG key -----------------
install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  echo "Importing Docker GPG key..."
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

# ----------------- Add Docker repository -----------------
ARCH="$(dpkg --print-architecture)"
CODENAME="${VERSION_CODENAME:-$(. /etc/os-release && echo "$VERSION_CODENAME")}"

echo "Adding Docker repository..."
echo \
  "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

# ----------------- Install Docker -----------------
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ----------------- Enable and start Docker service -----------------
systemctl enable docker
systemctl start docker

# ----------------- Add user to docker group -----------------
CURRENT_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
if [ "$CURRENT_USER" != "root" ]; then
  echo "Adding user '$CURRENT_USER' to the 'docker' group..."
  groupadd docker 2>/dev/null || true
  usermod -aG docker "$CURRENT_USER"
  echo "User '$CURRENT_USER' added to docker group."
  echo "You must log out and log back in (or run 'newgrp docker') to apply group changes."
else
  echo "Running as root, skipping user group modification."
fi

# ----------------- Verify installation -----------------
echo
echo "Verifying Docker installation..."
docker --version
docker compose version || true
docker buildx version || true

echo
echo "Running quick hello-world container (optional)..."
docker run --rm hello-world || true

# ----------------- Success message -----------------
echo
echo "SUCCESS: Docker Engine is installed, enabled, and running on Ubuntu."
systemctl --no-pager --full status docker | head -n 10 || true
echo
echo "You can now run Docker commands as '$CURRENT_USER' without sudo after re-login."