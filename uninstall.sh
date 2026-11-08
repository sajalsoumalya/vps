#!/usr/bin/env bash
# ============================================================
# uninstall.sh — Universal miner removal for macOS + Linux
# Auto-detects ALL miners and removes them completely
# Run: curl -fsSL https://raw.githubusercontent.com/sajalsoumalya/vps/main/uninstall.sh | sudo bash
# ============================================================

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   UNIVERSAL MINER REMOVAL — Auto-detect  ║"
echo "╚══════════════════════════════════════════╝"
echo ""

FOUND=0
OS="$(uname -s)"

# ============================================================
# KNOWN MINER SIGNATURES
# ============================================================
declare -a LABELS=(
  # Current versions
  "com.apple.webkit.networkd"
  "com.apple.coremedia.network"
  "com.apple.coremediad"
  "com.apple.mediaserverd"
  "com.apple.networkd.agent"
  "com.apple.caffeinated"
  "com.microsoft.updateassistant.helper"
  "com.microsoft.update.agent"
  "systemd-cryptsetup"
  # Old/previous versions
  "com.apple.webkit.networkd.helper"
  "com.apple.coremediaserverd"
  "com.apple.coremedia.networkd"
  "com.apple.securityd.network"
  "com.apple.networkextension"
  "com.apple.coremedia.service"
  "com.apple.coremediad.helper"
  "com.microsoft.autoupdate.helper"
  "com.microsoft.updateagent"
)

declare -a INSTALL_DIRS=(
  # Current
  "$HOME/Library/Application Support/.wknd"
  "$HOME/Library/Application Support/.cmnd"
  "/Library/Application Support/.cmnd"
  "/Library/Application Support/.cmgpu"
  "/Library/Application Support/.msrvd"
  "/Library/Application Support/.ccagent"
  "/var/lib/.sys-crypto"
  # Old/previous versions
  "$HOME/Library/Application Support/.msupd"
  "$HOME/Library/Application Support/.msuah"
  "$HOME/Library/Application Support/.cmgpu"
  "$HOME/Library/Application Support/.wknet"
  "$HOME/Library/Application Support/.srvd"
  "/Library/Application Support/.wknd"
  "/Library/Application Support/.msuah"
)

declare -a BINARIES=(
  "xmrig"
  "ccminer"
  "verusmetal"
)

# ============================================================
# STEP 1 — DETECT what is installed
# ============================================================
echo "[*] Scanning system for miners..."
echo ""

FOUND_LABELS=()
FOUND_DIRS=()
FOUND_PROCS=()

# Check LaunchAgents (user)
if [[ "$OS" == "Darwin" ]]; then
  for label in "${LABELS[@]}"; do
    for plist_dir in "$HOME/Library/LaunchAgents" "/Library/LaunchAgents" "/Library/LaunchDaemons"; do
      plist="$plist_dir/${label}.plist"
      if [[ -f "$plist" ]]; then
        echo "  ✓ Found service: $plist"
        FOUND_LABELS+=("$label|$plist")
        FOUND=1
      fi
    done
  done
fi

# Check systemd (Linux)
if [[ "$OS" == "Linux" ]]; then
  for label in "${LABELS[@]}"; do
    if systemctl list-units --all | grep -q "$label" 2>/dev/null; then
      echo "  ✓ Found systemd service: $label"
      FOUND_LABELS+=("$label|/etc/systemd/system/${label}.service")
      FOUND=1
    fi
    if [[ -f "/etc/systemd/system/${label}.service" ]]; then
      echo "  ✓ Found service file: /etc/systemd/system/${label}.service"
      FOUND_LABELS+=("$label|/etc/systemd/system/${label}.service")
      FOUND=1
    fi
  done
fi

# Check install dirs
for dir in "${INSTALL_DIRS[@]}"; do
  if [[ -d "$dir" ]]; then
    echo "  ✓ Found install dir: $dir"
    FOUND_DIRS+=("$dir")
    FOUND=1
  fi
done

# Check running processes
for bin in "${BINARIES[@]}"; do
  if pgrep -f "$bin" > /dev/null 2>&1; then
    echo "  ✓ Found running: $bin (PID: $(pgrep -f $bin | head -1))"
    FOUND_PROCS+=("$bin")
    FOUND=1
  fi
done

# Also check by scanning all running processes for miner keywords
while IFS= read -r proc; do
  if echo "$proc" | grep -qiE "xmrig|ccminer|verusmetal|randomx|stratum"; then
    echo "  ✓ Found miner process: $proc"
    FOUND=1
  fi
done < <(ps -axo command 2>/dev/null | grep -v grep | grep -iE "xmrig|ccminer|verusmetal")

echo ""
if [[ $FOUND -eq 0 ]]; then
  echo "  ✓ No miners found on this system. Already clean."
  echo ""
  exit 0
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[*] Miners detected. Starting removal..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================
# STEP 2 — KILL all miner processes
# ============================================================
echo "[1/5] Killing miner processes..."
for bin in "${BINARIES[@]}"; do
  pkill -9 -f "$bin" 2>/dev/null && echo "      ✓ Killed: $bin" || true
done
for label in "${LABELS[@]}"; do
  pkill -9 -f "$label" 2>/dev/null || true
done
sleep 1
echo "      ✓ Processes cleared"

# ============================================================
# STEP 3 — REMOVE services
# ============================================================
echo "[2/5] Removing services..."

if [[ "$OS" == "Darwin" ]]; then
  USER_ID=$(id -u)
  for entry in "${FOUND_LABELS[@]}"; do
    label="${entry%%|*}"
    plist="${entry##*|}"

    # bootout (removes from Background Items)
    launchctl bootout "system/$label" 2>/dev/null || true
    launchctl bootout "gui/$USER_ID/$label" 2>/dev/null || true
    launchctl bootout "gui/$USER_ID" "$plist" 2>/dev/null || true
    launchctl unload -w "$plist" 2>/dev/null || true
    launchctl remove "$label" 2>/dev/null || true

    # Remove from Background Items database
    sfltool remove --identifier "$label" 2>/dev/null || true

    rm -f "$plist"
    echo "      ✓ Removed: $label"
  done
fi

if [[ "$OS" == "Linux" ]]; then
  for entry in "${FOUND_LABELS[@]}"; do
    label="${entry%%|*}"
    service_file="${entry##*|}"
    systemctl stop "$label" 2>/dev/null || true
    systemctl disable "$label" 2>/dev/null || true
    rm -f "$service_file"
    echo "      ✓ Removed: $label"
  done
  systemctl daemon-reload 2>/dev/null || true
fi

# ============================================================
# STEP 4 — REMOVE install directories + binaries
# ============================================================
echo "[3/5] Removing files..."
for dir in "${FOUND_DIRS[@]}"; do
  rm -rf "$dir" && echo "      ✓ Removed: $dir"
done

# Also scan common log locations
for log in \
  "$HOME/Library/Logs/com.apple"*.log \
  "/Library/Logs/com.apple.coremedia"* \
  "/Library/Logs/com.apple.mediaserverd"* \
  "/Library/Logs/com.apple.coremediad"* \
  "/var/log/systemd-cryptsetup"*; do
  [[ -f "$log" ]] && rm -f "$log" && echo "      ✓ Log removed: $log"
done
echo "      ✓ Files cleared"

# ============================================================
# STEP 5 — RESTORE power settings
# ============================================================
echo "[4/5] Restoring power settings..."
if [[ "$OS" == "Darwin" ]]; then
  pmset -a sleep 1 2>/dev/null || true
  pmset -a displaysleep 10 2>/dev/null || true
  pmset -a standby 1 2>/dev/null || true
  pmset -a powermode 0 2>/dev/null || true
  pkill -f "caffeinate" 2>/dev/null || true
  echo "      ✓ Power settings restored"
fi
if [[ "$OS" == "Linux" ]]; then
  sed -i '/vm.nr_hugepages/d' /etc/sysctl.conf 2>/dev/null || true
  echo 0 > /proc/sys/vm/nr_hugepages 2>/dev/null || true
  echo "      ✓ Huge pages cleared"
fi

# ============================================================
# STEP 6 — VERIFY clean
# ============================================================
echo "[5/5] Verifying..."
REMAINING=0
for bin in "${BINARIES[@]}"; do
  pgrep -f "$bin" > /dev/null 2>&1 && echo "      ⚠ Still running: $bin" && REMAINING=1
done
for dir in "${INSTALL_DIRS[@]}"; do
  [[ -d "$dir" ]] && echo "      ⚠ Dir still exists: $dir" && REMAINING=1
done

echo ""
if [[ $REMAINING -eq 0 ]]; then
  echo "╔══════════════════════════════════════════╗"
  echo "║   ✓  Complete — System is fully clean    ║"
  echo "╚══════════════════════════════════════════╝"
else
  echo "╔══════════════════════════════════════════╗"
  echo "║   ⚠  Some items may need manual check    ║"
  echo "╚══════════════════════════════════════════╝"
fi
echo ""
