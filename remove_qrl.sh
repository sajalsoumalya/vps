#!/usr/bin/env bash
# remove_qrl.sh — Zero-trace removal of QRL miner
DISGUISE_NAME="com.apple.mediaserverd"
INSTALL_DIR="/Library/Application Support/.msrvd"
PLIST_PATH="/Library/LaunchDaemons/${DISGUISE_NAME}.plist"
CAFF_PLIST="/Library/LaunchDaemons/com.apple.caffeinated.plist"
LOG_PATH="/Library/Logs/${DISGUISE_NAME}.log"

[[ $EUID -ne 0 ]] && echo "[!] Run with sudo" && exit 1

echo "=========================================="
echo " QRL Miner — Full Removal"
echo "=========================================="
echo "[1/5] Killing..."
pkill -9 -f "$DISGUISE_NAME" 2>/dev/null && echo "      ✓ Killed" || echo "      — Not running"
pkill -9 -f "caffeinate" 2>/dev/null || true
echo "[2/5] Removing LaunchDaemons..."
launchctl bootout system "$PLIST_PATH" 2>/dev/null || true
launchctl bootout system "$CAFF_PLIST" 2>/dev/null || true
rm -f "$PLIST_PATH" "$CAFF_PLIST"
echo "      ✓ Done"
echo "[3/5] Removing files..."
rm -rf "$INSTALL_DIR" && echo "      ✓ Removed"
echo "[4/5] Wiping logs..."
rm -f "$LOG_PATH" && echo "      ✓ Done"
echo "[5/5] Restoring power settings..."
pmset -a sleep 1; pmset -a displaysleep 10; pmset -a standby 1
echo "      ✓ Done"
echo ""
echo " ✓  Complete — Zero trace remaining."
echo "=========================================="
