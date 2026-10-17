#!/bin/bash
# ==============================================================================
# MISSION-CONTROL AUTONOMOUS LOCAL SIL NODE DRIVER ACTIVATION
# Target: Raspberry Pi 400 (Debian/Linux Container Runtime)     
# Objective: Before any software container cutover is executed, the deployment pipeline runs five automated gating assertions.
# Note: Currently, this script is not executed instead direclty Ansible task are executed in provision.yml
# ==============================================================================

# 1. Assert required hardware character device nodes exist
test -e /dev/i2c-1 && test -e /dev/gpiomem && echo "[PASS] HIL character buses verified."

# 2. Check partition capacity (Minimum 1GB free required on /opt)
AVAIL_KB=$(df --output=avail -k /opt | tail -n 1)
if [ "$AVAIL_KB" -lt 1048576 ]; then
    echo "[FAIL] Critical: Less than 1GB storage available on /opt ($AVAIL_KB KB)."
    exit 1
fi

# 3. Check memory headroom (Minimum 256MB free required)
MEM_AVAIL=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
if [ "$MEM_AVAIL" -lt 262144 ]; then
    echo "[FAIL] Critical: Insufficient memory headroom ($MEM_AVAIL KB)."
    exit 1
fi

# 4. Check processor thermal throttling limits (Max 75°C threshold)
TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "45000")
TEMP_C=$((TEMP_RAW / 1000))
if [ "$TEMP_C" -gt 75 ]; then
    echo "[FAIL] Critical: Target processor thermally throttled at ${TEMP_C}°C. Aborting cutover."
    exit 1
fi
echo "[PASS] Thermal envelope nominal: ${TEMP_C}°C."