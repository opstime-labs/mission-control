#!/bin/bash
# ==============================================================================
# MISSION-CONTROL AUTONOMOUS LOCAL SIL NODE DRIVER ACTIVATION
# Target: Raspberry Pi 400 (Debian/Linux Container Runtime)
# Objective: Enable Broadcom I2C driver for SIL Node GPIO and I2C peripherals
# ==============================================================================
# 1. Update boot firmware to enable Broadcom I2C
CONFIG_PATH="/boot/firmware/config.txt"
[ ! -f "$CONFIG_PATH" ] && CONFIG_PATH="/boot/config.txt"

sudo sed -i -E 's/^#?dtparam=i2c_arm=.*/dtparam=i2c_arm=on/' "$CONFIG_PATH"
if ! grep -q "^dtparam=i2c_arm=on" "$CONFIG_PATH"; then
    echo "dtparam=i2c_arm=on" | sudo tee -a "$CONFIG_PATH"
fi

# 2. Register i2c-dev driver for persistent boot loading
if ! grep -q "^i2c-dev" /etc/modules; then
    echo "i2c-dev" | sudo tee -a /etc/modules
fi

# 3. Load dynamic device tree overlay live (No reboot required)
sudo dtoverlay i2c1
sudo modprobe i2c-dev

# 4. Verify character device nodes exist
ls -la /dev/i2c-1 /dev/gpiomem