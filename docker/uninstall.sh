#!/usr/bin/env bash
set -euo pipefail
set -o errtrace
trap 'echo "ERROR: command failed at line $LINENO" >&2; exit 1' ERR

# -------- Ubuntu-only guard --------
[ -f /etc/os-release ] || { echo "This script only supports Ubuntu." >&2; exit 1; }
. /etc/os-release
[ "${ID,,}" = "ubuntu" ] || { echo "This script only supports Ubuntu. Detected: ${ID}" >&2; exit 1; }

echo "Detected Ubuntu ${VERSION_CODENAME:-unknown}"
echo "Starting Docker full uninstall..."

# -------- Stop services (best-effort) --------
sudo systemctl stop docker.service docker.socket containerd.service 2>/dev/null || true
sudo systemctl --user stop docker.service docker.socket 2>/dev/null || true
sudo pkill -x dockerd 2>/dev/null || true

# -------- Best-effort cleanup of resources (if docker exists) --------
if command -v docker >/dev/null 2>&1; then
  echo "Cleaning Docker resources (best-effort)..."
  docker ps -q | xargs -r docker stop || true
  docker ps -aq | xargs -r docker rm -f || true
  docker images -q | xargs -r docker rmi -f || true
  docker volume ls -q | xargs -r docker volume rm -f || true
  docker network ls --format '{{.Name}}' \
    | grep -Ev '^(bridge|host|none)$' \
    | xargs -r docker network rm || true
fi

# -------- Purge packages (your list) --------
echo "Purging Docker packages..."
sudo apt-get purge -y \
  docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras || true

# Also purge common variants if present (safe no-ops if missing)
sudo apt-get purge -y docker.io docker-compose docker-scan-plugin || true

# -------- Remove repo + key (both .gpg and .asc forms) --------
echo "Removing Docker APT repo & key..."
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo rm -f /etc/apt/keyrings/docker.gpg
sudo rm -f /etc/apt/keyrings/docker.asc
sudo apt-get update -y || true

# -------- Remove data & config --------
echo "Removing Docker data & config..."
sudo rm -rf /var/lib/docker || true
sudo rm -rf /var/lib/containerd || true
sudo rm -rf /etc/docker || true
sudo rm -rf /etc/systemd/system/docker.service.d 2>/dev/null || true
sudo rm -f /var/run/docker.sock 2>/dev/null || true
sudo rm -f /usr/share/man/man1/docker* 2>/dev/null || true

# -------- Remove orphaned binaries (if not owned by any package) --------
maybe_rm_unowned() {
  local f="$1"
  [ -e "$f" ] || return 0
  if dpkg -S "$f" >/dev/null 2>&1; then
    # owned by a package — leave it to apt purge
    return 0
  fi
  echo "Removing orphaned binary: $f"
  sudo rm -f "$f" || true
}
maybe_rm_unowned /usr/bin/docker
maybe_rm_unowned /usr/bin/dockerd
maybe_rm_unowned /usr/bin/docker-init
maybe_rm_unowned /usr/bin/docker-proxy
maybe_rm_unowned /usr/local/bin/docker
maybe_rm_unowned /usr/local/bin/dockerd
maybe_rm_unowned /usr/local/bin/docker-compose
sudo rm -rf /usr/libexec/docker /usr/local/lib/docker /usr/lib/docker 2>/dev/null || true

# -------- Remove snap package if present --------
if command -v snap >/dev/null 2>&1 && snap list 2>/dev/null | grep -qi '^docker'; then
  echo "Removing Docker snap..."
  sudo snap stop docker || true
  sudo snap remove --purge docker || true
fi

# -------- Systemd + apt cleanup --------
sudo systemctl daemon-reload || true
sudo apt-get autoremove -y || true
sudo apt-get autoclean -y || true
hash -r || true

# -------- Verification --------
echo
echo "Verifying removal..."
if command -v docker >/dev/null 2>&1; then
  BIN="$(command -v docker)"
  echo "WARNING: 'docker' still on PATH at: $BIN"
  if dpkg -S "$BIN" >/dev/null 2>&1; then
    echo "Owned by package: $(dpkg -S "$BIN" | cut -d: -f1)"
  else
    echo "No owning package (custom file). Removing..."
    sudo rm -f "$BIN" || true
  fi
fi

hash -r || true
if command -v docker >/dev/null 2>&1; then
  echo "FAILED: docker command still exists."
  exit 1
fi

if systemctl list-unit-files | grep -q '^docker\.service'; then
  echo "WARNING: docker.service unit still present."
else
  echo "docker.service unit not present."
fi

echo
echo "SUCCESS: Docker has been fully uninstalled from this Ubuntu system."
