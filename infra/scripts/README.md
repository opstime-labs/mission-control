# sil-watchdog.sh Installation & Systemd Verification

Copy to SIL Node (RPI 400)
```bash
scp ./sil-watchdog.sh deployer@rpi-400:/opt/mission-control/bin/
```
On Raspberry Pi 400 (deployer@10.0.0.163):
```
# 1. Update the script and apply execute permissions
sudo tee /opt/mission-control/bin/sil-watchdog.sh > /dev/null < sil-watchdog.sh
sudo chmod 750 /opt/mission-control/bin/sil-watchdog.sh
sudo chown deployer:deployer /opt/mission-control/bin/sil-watchdog.sh

# 2. Restart and check systemd status
sudo systemctl restart sil-watchdog.service
sudo journalctl -u sil-watchdog.service -n 20 --no-pager
```