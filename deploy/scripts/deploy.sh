#!/bin/bash
set -euo pipefail

IMAGE_TAG=${1:-"latest"}
IMAGE="nexus.homelab.local:8082/mission-control/sensor-gateway:${IMAGE_TAG}"

echo "--> Target Image: ${IMAGE}"

# Append to the top of /opt/mission-control/deploy.sh
if ! docker pull "${IMAGE}" 2>/dev/null; then
    echo "--> Logging into Nexus Docker Registry..."
    echo "Nexus@1212" | docker login -u "admin" --password-stdin nexus.homelab.local:8082
    docker pull "${IMAGE}"
fi

# Identify active slot from NGINX config
if grep -q "127.0.0.1:5001" /etc/nginx/conf.d/mission-control.conf; then
    ACTIVE="blue"; TARGET="green"; TARGET_PORT=5002; ACTIVE_PORT=5001
else
    ACTIVE="green"; TARGET="blue"; TARGET_PORT=5001; ACTIVE_PORT=5002
fi

echo "--> Active Slot: [${ACTIVE}] (: ${ACTIVE_PORT}) | Deploying to: [${TARGET}] (: ${TARGET_PORT})"

# Pull and start new container on standby port
docker pull "${IMAGE}"
docker stop "mc-${TARGET}" 2>/dev/null || true
docker rm "mc-${TARGET}" 2>/dev/null || true

docker run -d --name "mc-${TARGET}" --restart unless-stopped -p "${TARGET_PORT}:8080" "${IMAGE}"

# Health Probe Verification
echo "--> Verifying health on port ${TARGET_PORT}..."
HEALTH_PASSED=false
for i in {1..10}; do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://127.0.0.1:${TARGET_PORT}/health" || echo "000")
    if [ "$STATUS" == "200" ]; then
        HEALTH_PASSED=true
        break
    fi
    sleep 2
done

if [ "$HEALTH_PASSED" = false ]; then
    echo "CRITICAL: Health check failed on ${TARGET}. Aborting cutover."
    docker stop "mc-${TARGET}"
    docker image rm "${IMAGE}"
    exit 1
fi

# Atomic Cutover
sudo /bin/sed -i "s/127.0.0.1:${ACTIVE_PORT}/127.0.0.1:${TARGET_PORT}/" /etc/nginx/conf.d/mission-control.conf
sudo /usr/sbin/nginx -t
sudo /bin/systemctl reload nginx

echo "--> Cutover complete. Slot [${TARGET}] is now live."
sleep 3
docker stop "mc-${ACTIVE}" 2>/dev/null || true
docker rm "mc-${ACTIVE}" 2>/dev/null || true

# Keep only the last 3 deployment images; purge dangling layers
echo "--> Cleaning up stale deployment images..."
docker image prune -f

# Retain the active running container images while stripping older tagged layers
docker images "nexus.homelab.local:8082/mission-control/sensor-gateway" --format "{{.Repository}}:{{.Tag}}" | \
  tail -n +4 | \
  xargs -r docker rmi 2>/dev/null || true
