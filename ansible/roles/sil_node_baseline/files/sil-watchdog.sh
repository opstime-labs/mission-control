#!/usr/bin/env bash
# ==============================================================================
# MISSION-CONTROL AUTONOMOUS LOCAL SIL NODE WATCHDOG
# Target: Raspberry Pi 400 (Debian/Linux Container Runtime)
# Objective: In-situ failure detection, single-slot rollback, double-fault lock
# ==============================================================================
set -euo pipefail

# Configuration
APP_BASE="/opt/mission-control"
ACTIVE_SLOT_FILE="${APP_BASE}/active_slot"
NGINX_CONF="${APP_BASE}/nginx/conf.d/gateway.conf"
PROBE_URL="http://127.0.0.1:8085/health"
MAX_FAILURES=3
CHECK_INTERVAL_SEC=5
TRIAGE_DIR="${APP_BASE}/triage"

# Slot Port Map
PORT_blue=5001
PORT_green=5002

log() {
    echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [WATCHDOG] $*"
}

# ------------------------------------------------------------------------------
# FAIL-SAFE CRITICAL STOP (DOUBLE FAULT)
# ------------------------------------------------------------------------------
engage_critical_stop() {
    local timestamp
    timestamp=$(date +%s)
    local incident_dir="${TRIAGE_DIR}/watchdog-doublefault-${timestamp}"

    log "CRITICAL: Fallback slot failed readiness! Engaging forensic fail-safe lockdown..."
    mkdir -p "${incident_dir}"

    # Capture state before modifications
    docker logs --tail 200 mc-blue > "${incident_dir}/mc-blue.log" 2>&1 || true
    docker logs --tail 200 mc-green > "${incident_dir}/mc-green.log" 2>&1 || true
    docker logs --tail 200 mc-proxy > "${incident_dir}/mc-proxy.log" 2>&1 || true
    dmesg -T | tail -n 150 > "${incident_dir}/dmesg.log" 2>&1 || true
    ss -tlpn > "${incident_dir}/sockets.log" 2>&1 || true

    # Deploy 503 Maintenance Ingress
    cat << 'NGINX_FAIL' > "${NGINX_CONF}"
server {
    listen 8085 default_server;
    server_name _;

    location / {
        default_type application/json;
        add_header Retry-After 300 always;
        return 503 '{"status":"CRITICAL_STOP","error":"SIL Node Quarantined by Local Watchdog. Both application slots degraded."}\n';
    }

    location /health {
        default_type text/plain;
        return 503 'Maintenance Mode - Watchdog Quarantined\n';
    }
}
NGINX_FAIL

    docker exec mc-proxy nginx -s reload || true
    docker stop mc-blue mc-green 2>/dev/null || true

    echo "quarantined_double_fault" > "${ACTIVE_SLOT_FILE}"
    log "QUARANTINE COMPLETE: Node locked in 503 mode. Triage path: ${incident_dir}"
    exit 2
}

# ------------------------------------------------------------------------------
# LOCAL ROLLBACK EXECUTION
# ------------------------------------------------------------------------------
trigger_local_rollback() {
    local failed_slot="$1"
    local fallback_slot=""
    local fallback_port=""

    if [[ "${failed_slot}" == "blue" ]]; then
        fallback_slot="green"
        fallback_port=${PORT_green}
    else
        fallback_slot="blue"
        fallback_port=${PORT_blue}
    fi

    log "ALERT: Slot [${failed_slot}] degraded. Initiating autonomous rollback to [${fallback_slot}]..."

    # 1. Start fallback container
    docker start "mc-${fallback_slot}" || engage_critical_stop

    # 2. Probe fallback readiness internally
    local ready=0
    for attempt in {1..10}; do
        if curl -s -f --connect-timeout 2 --max-time 3 "http://127.0.0.1:${fallback_port}/health" >/dev/null 2>&1; then
            ready=1
            break
        fi
        sleep 1
    done

    if [[ ${ready} -ne 1 ]]; then
        log "ERROR: Standby container mc-${fallback_slot} failed internal readiness probe on port ${fallback_port}."
        engage_critical_stop
    fi

    # 3. Dynamically resolve Bridge IP
    local docker_gw
    docker_gw=$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}')

    # 4. Atomically point NGINX to healthy fallback slot
    cat << NGINX_CONF_OUT > "${NGINX_CONF}"
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
NGINX_CONF_OUT

    docker exec mc-proxy nginx -t
    docker exec mc-proxy nginx -s reload

    # 5. Persist state and stop failed container
    echo "${fallback_slot}" > "${ACTIVE_SLOT_FILE}"
    docker stop "mc-${failed_slot}" 2>/dev/null || true

    log "SUCCESS: Autonomous rollback completed. Slot [${fallback_slot}] is now active."
}

# ------------------------------------------------------------------------------
# MAIN SUPERVISOR LOOP
# ------------------------------------------------------------------------------
consecutive_failures=0

log "Watchdog supervisor active on target node. Monitoring ${PROBE_URL} every ${CHECK_INTERVAL_SEC}s..."

while true; do
    if [[ ! -f "${ACTIVE_SLOT_FILE}" ]]; then
        sleep "${CHECK_INTERVAL_SEC}"
        continue
    fi

    active_slot=$(cat "${ACTIVE_SLOT_FILE}" | tr -d '[:space:]')

    # If the node is currently in quarantined state, hold monitoring
    if [[ "${active_slot}" == "quarantined_double_fault" ]]; then
        sleep "${CHECK_INTERVAL_SEC}"
        continue
    fi

    if curl -s -f --connect-timeout 2 --max-time 4 "${PROBE_URL}" > /dev/null 2>&1; then
        if [[ ${consecutive_failures} -gt 0 ]]; then
            log "Ingress recovered after transient fault. Resetting failure counter."
            consecutive_failures=0
        fi
    else
        consecutive_failures=$((consecutive_failures + 1))
        log "WARNING: Probe failed (${consecutive_failures}/${MAX_FAILURES}) for slot [${active_slot}]."

        if [[ ${consecutive_failures} -ge ${MAX_FAILURES} ]]; then
            log "THRESHOLD EXCEEDED: Health checks failed consecutively."
            trigger_local_rollback "${active_slot}"
            consecutive_failures=0
        fi
    fi

    sleep "${CHECK_INTERVAL_SEC}"
done


