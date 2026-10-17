#!/usr/bin/env bash
# ==============================================================================
# MISSION-CONTROL SIL TARGET NODE TEARDOWN & SANITIZATION SCRIPT
# Target: Raspberry Pi 400 (Debian ARM64 SIL Simulation Node)
# Standard: IEEE 828 / Controlled Goods Node Baseline Reset
# ==============================================================================
set -euo pipefail

# ANSI Color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} [$(date +'%Y-%m-%dT%H:%M:%SZ')] $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} [$(date +'%Y-%m-%dT%H:%M:%SZ')] $*"; }
log_success() { echo -e "${GREEN}[PASS]${NC} [$(date +'%Y-%m-%dT%H:%M:%SZ')] $*"; }
log_fatal()   { echo -e "${RED}[FATAL]${NC} [$(date +'%Y-%m-%dT%H:%M:%SZ')] $*"; exit 1; }

# Root privilege verification
if [[ "${EUID}" -ne 0 ]]; then
    log_fatal "This sanitization script modifies kernel packet filters and systemd units. Run as root or with sudo."
fi

log_info "Initiating deterministic teardown on SIL target host: $(hostname) ($(uname -m))"

# ------------------------------------------------------------------------------
# 1. STOP HOST-LEVEL SUPERVISORS & CONFLICTING SERVICES
# ------------------------------------------------------------------------------
log_info "1. Terminating local daemons, supervisors, and conflicting web servers..."

SERVICES_TO_STOP=(
    "sil-watchdog.service"
    "k3s"
    "k3s-agent"
    "nginx"
    "apache2"
    "lighttpd"
)

for svc in "${SERVICES_TO_STOP[@]}"; do
    if systemctl is-active --quiet "${svc}" 2>/dev/null; then
        systemctl stop "${svc}" 2>/dev/null || true
        log_warn "Stopped active systemd unit: ${svc}"
    fi
    if systemctl is-enabled --quiet "${svc}" 2>/dev/null; then
        systemctl disable "${svc}" 2>/dev/null || true
        log_warn "Disabled startup systemd unit: ${svc}"
    fi
done

# ------------------------------------------------------------------------------
# 2. PURGE ACTIVE DOCKER WORKLOADS & INGRESS CONTAINERS
# ------------------------------------------------------------------------------
log_info "2. Purging MissionControl workload slots and ingress reverse-proxies..."

CONTAINERS_TO_REMOVE=(
    "mc-proxy"
    "mc-green"
    "mc-blue"
    "mc-test"
)

for container in "${CONTAINERS_TO_REMOVE[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -Eq "^${container}\$"; then
        docker rm -f "${container}" >/dev/null 2>&1 || true
        log_warn "Force-removed container instance: ${container}"
    fi
done

# Prune dangling networks, build caches, and unlinked volumes
docker network prune -f >/dev/null 2>&1 || true
docker container prune -f >/dev/null 2>&1 || true
log_success "Container execution namespace sterilized."

# ------------------------------------------------------------------------------
# 3. TEAR DOWN STALE CNI, FLANNEL, AND VIRTUAL SOFTWARE BRIDGES
# ------------------------------------------------------------------------------
log_info "3. Dismantling virtual network bridges and stale SDN interfaces..."

INTERFACES_TO_UNLINK=(
    "cni0"
    "flannel.1"
    "tunl0"
    "kube-ipvs0"
)

for iface in "${INTERFACES_TO_UNLINK[@]}"; do
    if ip link show "${iface}" >/dev/null 2>&1; then
        ip link set "${iface}" down 2>/dev/null || true
        ip link delete "${iface}" 2>/dev/null || true
        log_warn "Unlinked virtual network interface: ${iface}"
    fi
done

# Purge leftover CNI network configuration and IPAM allocation states
rm -rf /var/lib/cni/ /etc/cni/net.d/*
log_success "Host SDN and CNI allocation tables purged."

# ------------------------------------------------------------------------------
# 4. FLUSH POLLUTED IPTABLES CHAINS & RESTORE DOCKER NAT FORWARDING
# ------------------------------------------------------------------------------
log_info "4. Flushing kernel packet filters, NAT tables, and lingering FORWARD drops..."

# Reset default chain policies to permit regeneration
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

# Flush all rules and delete custom user chains
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t raw -F
iptables -t raw -X

# Restart Docker daemon to reconstruct clean DOCKER, DOCKER-ISOLATION, and NAT chains
log_info "Restarting Docker daemon to reconstruct pristine bridge routing..."
systemctl restart docker
log_success "Kernel packet filter stack restored to baseline."

# ------------------------------------------------------------------------------
# 5. SANITIZE & RE-ESTABLISH DIRECTORY LAYOUT (/opt/mission-control)
# ------------------------------------------------------------------------------
log_info "5. Resetting /opt/mission-control operational state..."

APP_BASE="/opt/mission-control"

# Retain triage logs if present by rotating them, otherwise wipe cleanly
if [[ -d "${APP_BASE}/triage" ]] && [[ $(ls -A "${APP_BASE}/triage" 2>/dev/null) ]]; then
    ARCHIVE_DIR="/tmp/mc-triage-archive-$(date +%s)"
    mkdir -p "${ARCHIVE_DIR}"
    mv "${APP_BASE}/triage/"* "${ARCHIVE_DIR}/"
    log_warn "Previous forensic triage logs archived to: ${ARCHIVE_DIR}"
fi

rm -rf "${APP_BASE}"
mkdir -p "${APP_BASE}/nginx/conf.d"
mkdir -p "${APP_BASE}/bin"
mkdir -p "${APP_BASE}/triage"

# Initialize canonical state tracking file
echo "blue" > "${APP_BASE}/active_slot"

# Ensure POSIX ownership maps to unprivileged deployer user
chown -R deployer:deployer "${APP_BASE}"
chmod -R 755 "${APP_BASE}"
chmod 644 "${APP_BASE}/active_slot"
log_success "Directory structure restored. Baseline active slot initialized to [blue]."

# ------------------------------------------------------------------------------
# 6. VERIFY HARDWARE DEVICE NODES & SOCKET STATE
# ------------------------------------------------------------------------------
log_info "6. Auditing hardware character buses and listening sockets..."

# Verify hardware bus availability for HIL gating
for dev in "/dev/i2c-1" "/dev/gpiomem"; do
    if [[ -e "${dev}" ]]; then
        log_success "Hardware bus verified: ${dev}"
    else
        log_warn "Hardware bus node ${dev} not present. Ensure dynamic overlay is active."
    fi
done

# Verify unprivileged ingress port 8085 is completely free
if ss -tlpn | grep -q ':8085 '; then
    log_fatal "Port 8085 is still bound by another process! Check with: ss -tlpn | grep :8085"
else
    log_success "Ingress port 8085 is clean and unallocated."
fi

echo -e "\n=========================================================================="
log_success "SIL Node Teardown Complete. Host is ready for automated Ansible cutover."
echo "=========================================================================="