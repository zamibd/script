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
echo "Starting Docker uninstall..."

# ----------------- Warning & confirmation -----------------
# This will remove Docker packages, repo, keys AND ALL DATA (images, containers, volumes).
FORCE="${FORCE:-0}"
if [ "$FORCE" != "1" ]; then
  echo "WARNING: This will remove Docker Engine, CLI, Buildx, Compose, containerd, repository, keys,"
  echo "and ALL Docker data under /var/lib/docker and /var/lib/containerd."
  read -r -p "Proceed with FULL uninstall? [y/N]: " ans
  ans="${ans:-N}"
  case "${ans,,}" in
    y|yes) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

export DEBIAN_FRONTEND=noninteractive

# ----------------- Stop and disable services -----------------
echo "Stopping Docker services..."
systemctl stop docker.service docker.socket containerd.service 2>/dev/null || true
systemctl disable docker.service docker.socket containerd.service 2>/dev/null || true
systemctl daemon-reload || true

# ----------------- Remove containers/networks (best-effort) -----------------
# In case docker still runs; ignore failures if docker not available.
if command -v docker >/dev/null 2>&1; then
  echo "Attempting to remove all containers, images, volumes (best-effort)..."
  # Stop all running containers
  docker ps -q | xargs -r docker stop || true
  # Remove all containers
  docker ps -aq | xargs -r docker rm -f || true
  # Remove all images
  docker images -q | xargs -r docker rmi -f || true
  # Remove all volumes
  docker volume ls -q | xargs -r docker volume rm -f || true
  # Remove all networks except defaults
  docker network ls --format '{{.Name}}' \
    | grep -Ev '^(bridge|host|none)$' \
    | xargs -r docker network rm || true
fi

# ----------------- Purge packages -----------------
echo "Purging Docker packages..."
apt-get purge -y \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
  docker-ce-rootless-extras docker-scan-plugin docker-compose docker.io 2>/dev/null || true

# ----------------- Remove repo and key -----------------
echo "Removing Docker APT repo and key..."
rm -f /etc/apt/sources.list.d/docker.list
rm -f /etc/apt/keyrings/docker.gpg
apt-get update -y || true

# ----------------- Remove configuration and data -----------------
echo "Removing Docker data directories..."
rm -rf /var/lib/docker
rm -rf /var/lib/containerd
rm -rf /etc/docker
rm -rf /etc/systemd/system/docker.service.d 2>/dev/null || true
rm -f /var/run/docker.sock 2>/dev/null || true

# ----------------- Autoremove leftovers -----------------
apt-get autoremove -y
apt-get autoclean -y || true

# ----------------- Remove docker group if present -----------------
if getent group docker >/dev/null 2>&1; then
  # Only remove if group has no members (ignoring potential nss issues)
  if ! getent group docker | awk -F: '{print $4}' | grep -q '[^[:space:]]'; then
    groupdel docker 2>/dev/null || true
  fi
fi

# ----------------- Final checks -----------------
echo
echo "Verifying removal..."
if command -v docker >/dev/null 2>&1; then
  echo "WARNING: 'docker' command still exists on PATH:"
  command -v docker
  echo "You may need to remove it manually if it is from a custom install."
else
  echo "'docker' command not found (as expected)."
fi

if systemctl list-unit-files | grep -q '^docker\.service'; then
  echo "WARNING: docker.service unit still present."
else
  echo "docker.service unit not present."
fi

echo
echo "SUCCESS: Docker has been fully uninstalled from this Ubuntu system."