#!/usr/bin/env bash
# ================================================================
#  Route Technologies — DNS SaaS Server Setup Script
#  Supports : Ubuntu 22.04 / 24.04+ | Debian 12
#  Author   : Route Technologies
#  Version  : 1.0.0
# ================================================================

set -euo pipefail

# ── Colors & Styles ─────────────────────────────────────────────
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

RED='\033[0;31m';     GREEN='\033[0;32m'
YELLOW='\033[0;33m';  BLUE='\033[0;34m'
CYAN='\033[0;36m';    WHITE='\033[0;37m'

BRED='\033[1;31m';    BGREEN='\033[1;32m'
BYELLOW='\033[1;33m'; BBLUE='\033[1;34m'
BMAGENTA='\033[1;35m';BCYAN='\033[1;36m'
BWHITE='\033[1;37m'

BG_BLUE='\033[44m';   BG_CYAN='\033[46m'
BG_BLACK='\033[40m'

# ── Log Helpers ──────────────────────────────────────────────────
info()   { echo -e "  ${BCYAN}»${RESET}  $*"; }
ok()     { echo -e "  ${BGREEN}✔${RESET}  $*"; }
warn()   { echo -e "  ${BYELLOW}⚠${RESET}  ${YELLOW}$*${RESET}"; }
skip()   { echo -e "  ${DIM}${CYAN}↷  $* — already present, skipping${RESET}"; }
fail()   { echo -e "\n  ${BRED}✘  ERROR:${RESET} ${RED}$*${RESET}\n" >&2; exit 1; }
detail() { echo -e "     ${DIM}${WHITE}$*${RESET}"; }

step() {
    local num="$1" total="$2" title="$3"
    echo ""
    echo -e "  ${BG_BLUE}${BWHITE} STEP ${num}/${total} ${RESET}  ${BOLD}${BBLUE}${title}${RESET}"
    echo -e "  ${DIM}$(printf '%.0s─' {1..50})${RESET}"
}

banner() {
    clear
    echo ""
    echo -e "${BCYAN}${BOLD}"
    echo "   ██████╗  ██████╗ ██╗   ██╗████████╗███████╗"
    echo "   ██╔══██╗██╔═══██╗██║   ██║╚══██╔══╝██╔════╝"
    echo "   ██████╔╝██║   ██║██║   ██║   ██║   █████╗  "
    echo "   ██╔══██╗██║   ██║██║   ██║   ██║   ██╔══╝  "
    echo "   ██║  ██║╚██████╔╝╚██████╔╝   ██║   ███████╗"
    echo "   ╚═╝  ╚═╝ ╚═════╝  ╚═════╝   ╚═╝   ╚══════╝"
    echo -e "${RESET}"
    echo -e "   ${BMAGENTA}Route Technologies${RESET}  ${DIM}|${RESET}  ${CYAN}DNS SaaS Server Setup${RESET}"
    echo -e "   ${DIM}Ubuntu 22+/24+  ·  Debian 12  ·  v1.0.0${RESET}"
    echo ""
    echo -e "   ${DIM}$(printf '%.0s═' {1..46})${RESET}"
    echo ""
}

# ── Root Check ───────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && {
    echo -e "\n  ${BRED}✘  Root required.${RESET}  Run: ${BYELLOW}sudo bash $0${RESET}\n"
    exit 1
}

banner

# ────────────────────────────────────────────────────────────────
# STEP 1 — OS Detection
# ────────────────────────────────────────────────────────────────
step 1 8 "OS Detection"

[[ -f /etc/os-release ]] || fail "/etc/os-release not found"
source /etc/os-release

OS_ID="${ID,,}"
OS_VERSION="${VERSION_ID}"

case "$OS_ID" in
    ubuntu)
        MAJOR=$(echo "$OS_VERSION" | cut -d. -f1)
        [[ $MAJOR -ge 22 ]] || fail "Ubuntu 22.04+ required. Found: $OS_VERSION"
        CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"
        ok "${BGREEN}Ubuntu ${OS_VERSION}${RESET} (${CODENAME}) — supported"
        detail "Codename : $CODENAME"
        detail "Arch     : $(dpkg --print-architecture)"
        ;;
    debian)
        MAJOR=$(echo "$OS_VERSION" | cut -d. -f1)
        [[ $MAJOR -ge 12 ]] || fail "Debian 12+ required. Found: $OS_VERSION"
        CODENAME="${VERSION_CODENAME}"
        ok "${BGREEN}Debian ${OS_VERSION}${RESET} (${CODENAME}) — supported"
        detail "Codename : $CODENAME"
        detail "Arch     : $(dpkg --print-architecture)"
        ;;
    *)
        fail "Unsupported OS: '$OS_ID'. Only Ubuntu 22+/24+ or Debian 12 are supported."
        ;;
esac

export DEBIAN_FRONTEND=noninteractive

# ────────────────────────────────────────────────────────────────
# STEP 2 — System Update & Upgrade
# ────────────────────────────────────────────────────────────────
step 2 8 "System Update & Upgrade"

info "Running apt update..."
apt-get update -qq
ok "Package lists refreshed"

info "Running apt upgrade (this may take a while)..."
apt-get upgrade -y -qq \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
ok "System packages upgraded successfully"

# ────────────────────────────────────────────────────────────────
# STEP 3 — Essential Packages
# ────────────────────────────────────────────────────────────────
step 3 8 "Essential Packages"

PKGS=(
    curl wget git ufw fail2ban
    unattended-upgrades
    ca-certificates gnupg lsb-release
    htop net-tools make build-essential
)

TO_INSTALL=()
for pkg in "${PKGS[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        skip "${CYAN}${pkg}${RESET}"
    else
        info "Queued    : ${YELLOW}${pkg}${RESET}"
        TO_INSTALL+=("$pkg")
    fi
done

if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
    echo ""
    info "Installing ${BYELLOW}${#TO_INSTALL[@]}${RESET} package(s)..."
    apt-get install -y -qq "${TO_INSTALL[@]}"
    ok "All packages installed"
else
    ok "All essential packages already present"
fi

# ────────────────────────────────────────────────────────────────
# STEP 4 — Docker & Docker Compose
# ────────────────────────────────────────────────────────────────
step 4 8 "Docker Engine & Docker Compose"

install_docker() {
    info "Adding Docker official GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    ok "GPG key saved"

    info "Adding Docker apt repository..."
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/${OS_ID} ${CODENAME} stable" \
        | tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update -qq
    ok "Repository configured"

    info "Installing Docker CE + plugins..."
    apt-get install -y -qq \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    ok "Docker installed & service started"
}

if command -v docker &>/dev/null; then
    OLD_VER=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
    info "Docker found (${YELLOW}v${OLD_VER}${RESET}) — checking for upgrades..."
    apt-get install -y -qq --only-upgrade \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
    NEW_VER=$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)
    if [[ "$OLD_VER" != "$NEW_VER" ]]; then
        ok "Docker upgraded: ${YELLOW}v${OLD_VER}${RESET} → ${BGREEN}v${NEW_VER}${RESET}"
    else
        ok "Docker is up-to-date: ${BGREEN}v${NEW_VER}${RESET}"
    fi
else
    install_docker
fi

if docker compose version &>/dev/null 2>&1; then
    DC_VER=$(docker compose version --short 2>/dev/null || echo "installed")
    ok "Docker Compose plugin: ${BGREEN}v${DC_VER}${RESET}"
else
    warn "Docker Compose plugin not available"
fi

detail "Storage driver : $(docker info --format '{{.Driver}}' 2>/dev/null || echo 'N/A')"
detail "Docker root    : $(docker info --format '{{.DockerRootDir}}' 2>/dev/null || echo 'N/A')"

# ────────────────────────────────────────────────────────────────
# STEP 5 — Timezone
# ────────────────────────────────────────────────────────────────
step 5 8 "Timezone Configuration"

CURRENT_TZ=$(timedatectl show -p Timezone --value 2>/dev/null || echo "unknown")
if [[ "$CURRENT_TZ" == "Asia/Dhaka" ]]; then
    ok "Timezone already ${BGREEN}Asia/Dhaka${RESET}"
else
    info "Changing: ${YELLOW}${CURRENT_TZ}${RESET} → ${BGREEN}Asia/Dhaka${RESET}"
    timedatectl set-timezone Asia/Dhaka
    ok "Timezone set to ${BGREEN}Asia/Dhaka${RESET}"
fi
detail "Local time : $(date '+%A, %d %B %Y  %H:%M:%S %Z')"

# ────────────────────────────────────────────────────────────────
# STEP 6 — UFW Firewall
# ────────────────────────────────────────────────────────────────
step 6 8 "UFW Firewall Rules"

command -v ufw &>/dev/null || apt-get install -y -qq ufw

ufw --force reset > /dev/null 2>&1
ufw default deny incoming  > /dev/null
ufw default allow outgoing > /dev/null
ok "Default policy → ${BRED}DENY${RESET} incoming / ${BGREEN}ALLOW${RESET} outgoing"
echo ""

open_port() {
    local port="$1" label="$2"
    ufw allow "$port" > /dev/null
    local proto num
    proto=$(echo "$port" | cut -d/ -f2 | tr '[:lower:]' '[:upper:]')
    num=$(echo "$port" | cut -d/ -f1)
    echo -e "  ${BGREEN}✔${RESET}  ${BOLD}${BWHITE}${num}${RESET}/${CYAN}${proto}${RESET}   — ${WHITE}${label}${RESET}"
}

open_port "22/tcp"  "SSH — Admin Access"
open_port "80/tcp"  "HTTP — ACME / Certificate Renewal"
open_port "443/tcp" "HTTPS — DoH (DNS-over-HTTPS)"
open_port "53/tcp"  "DNS — Plain TCP"
open_port "53/udp"  "DNS — Plain UDP"
open_port "853/tcp" "DoT — DNS-over-TLS"

echo ""
ufw --force enable > /dev/null
ok "UFW firewall ${BGREEN}enabled${RESET}"

# ────────────────────────────────────────────────────────────────
# STEP 7 — Kernel Tuning
# ────────────────────────────────────────────────────────────────
step 7 8 "Kernel Tuning (DNS / DoT Optimized)"

SYSCTL_FILE="/etc/sysctl.d/99-routedns.conf"

cat > "$SYSCTL_FILE" << 'EOF'
# ── Route Technologies — DNS SaaS Kernel Tuning ──────────────────
# Applied by: dns-saas-setup.sh

# UDP/TCP Buffers — high-volume DNS traffic
net.core.rmem_max           = 16777216
net.core.wmem_max           = 16777216
net.core.rmem_default       = 262144
net.core.wmem_default       = 262144

# Network Queue
net.core.netdev_max_backlog = 5000
net.core.somaxconn          = 65535

# TCP Optimizations
net.ipv4.tcp_fastopen        = 3
net.ipv4.tcp_tw_reuse        = 1
net.ipv4.tcp_fin_timeout     = 15
net.ipv4.tcp_keepalive_time  = 300
net.ipv4.tcp_keepalive_probes= 5
net.ipv4.tcp_keepalive_intvl = 15

# DoT / TLS Connection Queue
net.ipv4.tcp_max_syn_backlog = 8192

# Docker — IP Forwarding
net.ipv4.ip_forward = 1

# File Descriptors
fs.file-max = 1000000
EOF

info "Applying sysctl parameters..."
sysctl -p "$SYSCTL_FILE" > /dev/null 2>&1
ok "Kernel parameters applied"
detail "Config file  : $SYSCTL_FILE"
detail "rmem_max     : $(sysctl -n net.core.rmem_max)"
detail "somaxconn    : $(sysctl -n net.core.somaxconn)"
detail "tcp_fastopen : $(sysctl -n net.ipv4.tcp_fastopen)"
detail "ip_forward   : $(sysctl -n net.ipv4.ip_forward)"

# ────────────────────────────────────────────────────────────────
# STEP 8 — Disable systemd-resolved
# ────────────────────────────────────────────────────────────────
step 8 8 "Disable systemd-resolved (Free Port 53)"

if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    info "Stopping systemd-resolved..."
    systemctl disable --now systemd-resolved
    ok "systemd-resolved ${BRED}stopped & disabled${RESET}"
else
    ok "systemd-resolved was already inactive"
fi

if [[ -L /etc/resolv.conf ]]; then
    info "Replacing symlink /etc/resolv.conf with static file..."
    rm -f /etc/resolv.conf
    cat > /etc/resolv.conf << 'EOF'
# Route Technologies — Static DNS resolvers
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 8.8.4.4
EOF
    ok "/etc/resolv.conf → static nameservers written"
    detail "Nameservers : 8.8.8.8 / 1.1.1.1 / 8.8.4.4"
else
    ok "/etc/resolv.conf is already a regular file"
fi

# ════════════════════════════════════════════════════════════════
# SUMMARY
# ════════════════════════════════════════════════════════════════
echo ""
echo ""
echo -e "${BG_CYAN}${BOLD}                                                      ${RESET}"
echo -e "${BG_CYAN}${BOLD}   Route Technologies  —  Setup Complete  ✔            ${RESET}"
echo -e "${BG_CYAN}${BOLD}                                                      ${RESET}"
echo ""

# ── System ──────────────────────────────────────────────────────
echo -e "  ${BMAGENTA}╔══ System ═══════════════════════════════════════╗${RESET}"
echo -e "  ${BMAGENTA}║${RESET}  OS         ${DIM}:${RESET}  ${BWHITE}${PRETTY_NAME}${RESET}"
echo -e "  ${BMAGENTA}║${RESET}  Kernel     ${DIM}:${RESET}  ${BWHITE}$(uname -r)${RESET}"
echo -e "  ${BMAGENTA}║${RESET}  Arch       ${DIM}:${RESET}  ${BWHITE}$(uname -m)${RESET}"
echo -e "  ${BMAGENTA}║${RESET}  Timezone   ${DIM}:${RESET}  ${BWHITE}$(timedatectl show -p Timezone --value)${RESET}  —  $(date '+%H:%M:%S')"
echo -e "  ${BMAGENTA}╚═════════════════════════════════════════════════╝${RESET}"
echo ""

# ── Tools ───────────────────────────────────────────────────────
echo -e "  ${BCYAN}╔══ Installed Tools ══════════════════════════════╗${RESET}"

_row() {
    local icon="$1" name="$2" val="$3"
    printf "  ${BCYAN}║${RESET}  %b  %-12s${DIM}:${RESET}  ${BWHITE}%s${RESET}\n" "$icon" "$name" "$val"
}

if command -v git &>/dev/null; then
    _row "${BGREEN}✔${RESET}" "git" "v$(git --version | awk '{print $3}')"
else
    _row "${BRED}✘${RESET}" "git" "not found"
fi

if command -v make &>/dev/null; then
    _row "${BGREEN}✔${RESET}" "make" "v$(make --version | head -1 | grep -oP '\d+\.\d+(\.\d+)?')"
else
    _row "${BRED}✘${RESET}" "make" "not found"
fi

if command -v docker &>/dev/null; then
    _row "${BGREEN}✔${RESET}" "docker" "v$(docker --version | grep -oP '\d+\.\d+\.\d+' | head -1)"
else
    _row "${BRED}✘${RESET}" "docker" "not found"
fi

if docker compose version &>/dev/null 2>&1; then
    _row "${BGREEN}✔${RESET}" "compose" "v$(docker compose version --short 2>/dev/null || echo '?')"
else
    _row "${BRED}✘${RESET}" "compose" "not available"
fi

if command -v fail2ban-client &>/dev/null; then
    _row "${BGREEN}✔${RESET}" "fail2ban" "v$(fail2ban-client --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)"
else
    _row "${BRED}✘${RESET}" "fail2ban" "not found"
fi

if command -v curl &>/dev/null; then
    _row "${BGREEN}✔${RESET}" "curl" "v$(curl --version | head -1 | awk '{print $2}')"
fi

echo -e "  ${BCYAN}╚═════════════════════════════════════════════════╝${RESET}"
echo ""

# ── Firewall ─────────────────────────────────────────────────────
echo -e "  ${BYELLOW}╔══ Firewall (UFW) ═══════════════════════════════╗${RESET}"
UFW_STATE=$(ufw status | head -1 | awk '{print $NF}')
echo -e "  ${BYELLOW}║${RESET}  Status     ${DIM}:${RESET}  ${BGREEN}${UFW_STATE}${RESET}"
echo -e "  ${BYELLOW}║${RESET}  ${BGREEN}✔${RESET}  ${BOLD}  22${RESET}/tcp  —  SSH"
echo -e "  ${BYELLOW}║${RESET}  ${BGREEN}✔${RESET}  ${BOLD}  53${RESET}/tcp  —  DNS Plain TCP"
echo -e "  ${BYELLOW}║${RESET}  ${BGREEN}✔${RESET}  ${BOLD}  53${RESET}/udp  —  DNS Plain UDP"
echo -e "  ${BYELLOW}║${RESET}  ${BGREEN}✔${RESET}  ${BOLD}  80${RESET}/tcp  —  HTTP / ACME"
echo -e "  ${BYELLOW}║${RESET}  ${BGREEN}✔${RESET}  ${BOLD} 443${RESET}/tcp  —  HTTPS / DoH"
echo -e "  ${BYELLOW}║${RESET}  ${BGREEN}✔${RESET}  ${BOLD} 853${RESET}/tcp  —  DoT (DNS-over-TLS)"
echo -e "  ${BYELLOW}╚═════════════════════════════════════════════════╝${RESET}"
echo ""

# ── Kernel & DNS ──────────────────────────────────────────────────
echo -e "  ${BBLUE}╔══ Kernel Tuning & DNS ══════════════════════════╗${RESET}"
echo -e "  ${BBLUE}║${RESET}  Sysctl file ${DIM}:${RESET}  ${CYAN}${SYSCTL_FILE}${RESET}"
echo -e "  ${BBLUE}║${RESET}  rmem_max    ${DIM}:${RESET}  $(sysctl -n net.core.rmem_max)"
echo -e "  ${BBLUE}║${RESET}  somaxconn   ${DIM}:${RESET}  $(sysctl -n net.core.somaxconn)"
echo -e "  ${BBLUE}║${RESET}  ip_forward  ${DIM}:${RESET}  $(sysctl -n net.ipv4.ip_forward)"

if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    echo -e "  ${BBLUE}║${RESET}  Port 53     ${DIM}:${RESET}  ${BRED}systemd-resolved still running!${RESET}"
else
    echo -e "  ${BBLUE}║${RESET}  Port 53     ${DIM}:${RESET}  ${BGREEN}free${RESET}  (systemd-resolved disabled)"
fi
echo -e "  ${BBLUE}╚═════════════════════════════════════════════════╝${RESET}"
echo ""

echo -e "  ${BGREEN}${BOLD}✔  Server is ready for DNS SaaS deployment!${RESET}"
echo ""
echo -e "  ${BYELLOW}⚠  Reboot recommended to fully apply kernel changes${RESET}"
echo -e "     ${BOLD}\$ reboot${RESET}"
echo ""
echo -e "  ${DIM}Route Technologies · routedns.io · $(date '+%Y')${RESET}"
echo ""
