#!/usr/bin/env bash
# ==============================================================================
# MISSION-CONTROL AUTONOMOUS LOCAL SIL NODE WATCHDOG
# Target Node: Raspberry Pi 400 (Debian ARM64 SIL Target)
# Mandate: Leonardo DRS (Kanata) - C#/.NET Mission Systems[cite: 10, 11]
# Standard: IEEE 828 Configuration Management & Autonomous Survival[cite: 10, 11]
# ==============================================================================
set -euo pipefail

# ------------------------------------------------------------------------------
# CONFIGURATION & TOPOLOGY DEFINITION
# ------------------------------------------------------------------------------
APP_BASE="/opt/mission-control"
ACTIVE_SLOT_FILE="${APP_BASE}/active_slot"
NGINX_CONF="${APP_BASE}/nginx/conf.d/gateway.conf"
PROBE_URL="http://127.0.0.1:8085/health"
TRIAGE_DIR="${APP_BASE}/triage"

# Timing & Retry Thresholds
MAX_FAILURES=3
CHECK_INTERVAL_SEC=5
PROBE_TIMEOUT_SEC=3
STANDBY_BOOT_TIMEOUT_SEC=15

# Slot Port Allocations
PORT_blue=5001
PORT_green=5002

log() {
    echo "[$(date -u +'\%Y-\%m-\%dT\%H:\%M:\%SZ')] [WATCHDOG]$*"
}

# ------------------------------------------------------------------------------
# DOUBLE-FAULT CRITICAL STOP (FORENSIC LOCKDOWN)
# ------------------------------------------------------------------------------
engage_critical_stop() {
    local incident_epoch
    incident_epoch=$(date +%s)
    local incident_dir="${TRIAGE_DIR}/watchdog-doublefault-${incident_epoch}"

    log "CRITICAL: Fallback container failed internal readiness! Engaging forensic fail-safe lockdown..."
    mkdir -p "${incident_dir}"

    # 1. Capture system & process state before altering runtime
    docker logs --tail 300 mc-blue > "${incident_dir}/mc-blue.log" 2>&1 || true
    docker logs --tail 300 mc-green > "${incident_dir}/mc-green.log" 2>&1 || true
    docker logs --tail 300 mc-proxy > "${incident_dir}/mc-proxy.log" 2>&1 || true
    dmesg -T | tail -n 200 > "${incident_dir}/dmesg.log" 2>&1 || true
    ss -tlpn > "${incident_dir}/listening_sockets.log" 2>&1 || true
    free -m > "${incident_dir}/memory.log" 2>&1 || true

    # 2. Deploy 503 Maintenance Ingress (Isolates edge clients, stops queue congestion)
    cat << 'NGINX_503' > "${NGINX_CONF}"
server {
    listen 8085 default_server;
    server_name _;

    location / {
        default_type application/json;
        add_header Retry-After 300 always;
        return 503 '{"status":"CRITICAL_STOP","error":"SIL Node Quarantined by Local Autonomous Watchdog. Both application slots degraded. Triage in progress."}\n';
    }

    location /health {
        default_type text/plain;
        add_header Retry-After 300 always;
        return 503 'Maintenance Mode - Watchdog Double Fault Lock\n';
    }
}
NGINX_503

    # Reload proxy to take traffic offline
    docker exec mc-proxy nginx -t >/dev/null 2>&1 && docker exec mc-proxy nginx -s reload || true

    # 3. Terminate failed application containers to preserve host resources
    docker stop mc-blue mc-green 2>/dev/null || true

    # 4. Lock state file to prevent unvetted automated redeployments
    echo "quarantined_double_fault" > "${ACTIVE_SLOT_FILE}"

    log "QUARANTINE COMPLETE: Node locked in 503 Maintenance Mode. Forensic logs stored at: ${incident_dir}"
    exit 2
}

# ------------------------------------------------------------------------------
# LOCAL AUTONOMOUS ROLLBACK ENGINE
# ------------------------------------------------------------------------------
trigger_local_rollback() {
    local failed_slot="$1"
    local fallback_slot="green"
    local fallback_port=${PORT_green}

    if [[ "${failed_slot}" == "green" ]]; then
        fallback_slot="blue"
        fallback_port=${PORT_blue}
    fi

    log "ALERT: Active slot [${failed_slot}] degraded. Initiating autonomous rollback to standby slot [${fallback_slot}]..."

    # 1. Start fallback container
    if ! docker start "mc-${fallback_slot}" >/dev/null 2>&1; then
        log "ERROR: Failed to issue 'docker start mc-${fallback_slot}'."
        engage_critical_stop
    fi

    # 2. Poll fallback container readiness internally before redirecting ingress
    local is_ready=0
    log "Verifying standby slot readiness on http://127.0.0.1:${fallback_port}/health..."
    for ((attempt=1; attempt<=STANDBY_BOOT_TIMEOUT_SEC; attempt++)); do
        if curl -s -f --connect-timeout 2 --max-time "${PROBE_TIMEOUT_SEC}" "http://127.0.0.1:${fallback_port}/health" >/dev/null 2>&1; then
            is_ready=1
            break
        fi
        sleep 1
    done

    if [[ ${is_ready} -ne 1 ]]; then
        log "ERROR: Standby container mc-${fallback_slot} failed internal readiness checks after${STANDBY_BOOT_TIMEOUT_SEC}s."
        engage_critical_stop
    fi

    # 3. Dynamically resolve Docker Bridge Gateway IP
    local docker_gw
    docker_gw=$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null || echo "172.17.0.1")

    # 4. Generate new NGINX upstream route configuration
    cat << NGINX_ROUTING > "${NGINX_CONF}"
upstream mission_control_backend {
    server ${docker_gw}:${fallback_port} max_fails=3 fail_timeout=5s;
    keepalive 32;
}

server {
    listen 8085 default_server;
    server_name _;

    proxy_connect_timeout 2s;
    proxy_read_timeout 5s;
    proxy_send_timeout 2s;

    location /health {
        proxy_pass http://mission_control_backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host \$host;
        access_log off;
    }

    location / {
        proxy_pass http://mission_control_backend;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINX_ROUTING

    # 5. Validate configuration syntax and reload NGINX gracefully
    if ! docker exec mc-proxy nginx -t >/dev/null 2>&1; then
        log "ERROR: Generated NGINX syntax validation failed."
        engage_critical_stop
    fi
    docker exec mc-proxy nginx -s reload

    # 6. Update active slot marker and terminate degraded container
    echo "${fallback_slot}" > "${ACTIVE_SLOT_FILE}"
    docker stop "mc-${failed_slot}" >/dev/null 2>&1 || true

    log "SUCCESS: Autonomous rollback complete. Traffic restored to slot [${fallback_slot}] on port [${fallback_port}]."
}

# ------------------------------------------------------------------------------
# SUPERVISOR CONTROL LOOP
# ------------------------------------------------------------------------------
consecutive_failures=0

log "Watchdog supervisor operational. Polling ${PROBE_URL} every${CHECK_INTERVAL_SEC}s..."

while true; do
    if [[ ! -f "${ACTIVE_SLOT_FILE}" ]]; then
        sleep "${CHECK_INTERVAL_SEC}"
        continue
    fi

    active_slot=$(cat "${ACTIVE_SLOT_FILE}" | tr -d '[:space:]')

    # If already quarantined, do not attempt automatic recovery
    if [[ "${active_slot}" == "quarantined_double_fault" ]]; then
        sleep "${CHECK_INTERVAL_SEC}"
        continue
    fi

    # Probe Ingress Edge Socket
    if curl -s -f --connect-timeout 2 --max-time "${PROBE_TIMEOUT_SEC}" "${PROBE_URL}" >/dev/null 2>&1; then
        if [[ ${consecutive_failures} -gt 0 ]]; then
            log "Ingress self-healed after transient spike. Resetting failure counter to 0."
            consecutive