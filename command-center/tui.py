#!/usr/bin/env python3
"""
Mining Command Center — TUI Dashboard
Shows all nodes live, control with keyboard
Run: python3 tui.py --url https://cc.snumcaj.com --token YOUR_TOKEN
"""

import os, sys, time, json, threading, argparse
import urllib.request, urllib.error

try:
    import curses
except ImportError:
    print("curses not available")
    sys.exit(1)

CC_URL = "https://cc.snumcaj.com"
CC_TOKEN = "changeme123"
REFRESH = 5

def api_get(path):
    req = urllib.request.Request(f"{CC_URL}{path}",
        headers={"Authorization": f"Bearer {CC_TOKEN}"})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return json.loads(r.read())
    except:
        return None

def api_post(path, data):
    body = json.dumps(data).encode()
    req = urllib.request.Request(f"{CC_URL}{path}", data=body,
        headers={"Authorization": f"Bearer {CC_TOKEN}",
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return json.loads(r.read())
    except:
        return None

def send_command(action, target="all", payload=""):
    return api_post("/command", {"action": action, "target": target, "payload": payload})

def send_wol(mac_address):
    return api_post("/wol", {"mac": mac_address})

class Dashboard:
    def __init__(self, stdscr):
        self.scr = stdscr
        self.data = {"nodes": 0, "online": 0, "total_hashrate": "0", "nodes_list": []}
        self.selected = 0
        self.message = ""
        self.message_time = 0
        self.running = True
        self.lock = threading.Lock()
        curses.start_color()
        curses.use_default_colors()
        curses.init_pair(1, curses.COLOR_GREEN,  -1)
        curses.init_pair(2, curses.COLOR_RED,    -1)
        curses.init_pair(3, curses.COLOR_YELLOW, -1)
        curses.init_pair(4, curses.COLOR_CYAN,   -1)
        curses.init_pair(5, curses.COLOR_WHITE,  -1)
        curses.init_pair(6, curses.COLOR_MAGENTA,-1)
        curses.curs_set(0)
        self.scr.timeout(500)

    def fetch_loop(self):
        while self.running:
            d = api_get("/status")
            if d:
                with self.lock:
                    self.data = d
            time.sleep(REFRESH)

    def set_msg(self, msg):
        self.message = msg
        self.message_time = time.time()

    def draw(self):
        self.scr.erase()
        h, w = self.scr.getmaxyx()
        with self.lock:
            data = self.data
            nodes = data.get("nodes_list", [])

        # ── Header ──
        title = "⛏  MINING COMMAND CENTER"
        self.scr.attron(curses.color_pair(6) | curses.A_BOLD)
        self.scr.addstr(0, max(0,(w-len(title))//2), title[:w])
        self.scr.attroff(curses.color_pair(6) | curses.A_BOLD)

        # Stats bar
        stats = f"  Nodes: {data.get('nodes',0)}  Online: {data.get('online',0)}  Total: {data.get('total_hashrate','0')}  [{time.strftime('%H:%M:%S')}]"
        self.scr.attron(curses.color_pair(4))
        self.scr.addstr(1, 0, stats[:w])
        self.scr.attroff(curses.color_pair(4))

        # Separator
        self.scr.attron(curses.color_pair(5))
        self.scr.addstr(2, 0, "─" * (w-1))
        self.scr.attroff(curses.color_pair(5))

        # Column headers
        hdr = f"{'':2}{'ST':2} {'NODE':<14} {'IP':<16} {'HASHRATE':<12} {'MINER':<8} {'MACOS':<8} {'CORES':<5} {'LAST SEEN':<20}"
        self.scr.attron(curses.A_BOLD | curses.color_pair(3))
        self.scr.addstr(3, 0, hdr[:w])
        self.scr.attroff(curses.A_BOLD | curses.color_pair(3))
        self.scr.addstr(4, 0, "─" * (w-1))

        # Node rows
        max_rows = h - 10
        for i, node in enumerate(nodes[:max_rows]):
            y = 5 + i
            online = "online" in node.get("status","")
            status_sym = "●" if online else "○"
            color = curses.color_pair(1) if online else curses.color_pair(2)
            selected = (i == self.selected)

            row = f"  {status_sym}  {node.get('hostname','?'):<14} {node.get('ip','?'):<16} {node.get('hashrate','0'):<12} {node.get('miner','?'):<8} {node.get('macos','?'):<8} {str(node.get('cores','?')):<5} {node.get('last_seen','?'):<20}"

            if selected:
                self.scr.attron(curses.A_REVERSE)
            self.scr.attron(color)
            self.scr.addstr(y, 0, row[:w-1])
            self.scr.attroff(color)
            if selected:
                self.scr.attroff(curses.A_REVERSE)

        # ── Bottom controls ──
        ctrl_y = h - 4
        self.scr.addstr(ctrl_y, 0, "─" * (w-1))
        ctrl_y += 1

        controls = [
            ("V", "Mine VRSC all"),
            ("X", "Mine XMR all"),
            ("S", "Stop all"),
            ("R", "Remove all"),
            ("U", "Update all"),
            ("W", "Wake-on-LAN"),
            ("↑↓", "Select"),
            ("Enter", "Node cmd"),
            ("Q", "Quit"),
        ]
        ctrl_str = "  ".join(f"[{k}]{v}" for k,v in controls)
        self.scr.attron(curses.color_pair(3))
        self.scr.addstr(ctrl_y, 0, ctrl_str[:w-1])
        self.scr.attroff(curses.color_pair(3))

        # Message bar
        if self.message and time.time() - self.message_time < 4:
            self.scr.attron(curses.color_pair(1) | curses.A_BOLD)
            self.scr.addstr(h-2, 0, f"  ✓ {self.message}"[:w-1])
            self.scr.attroff(curses.color_pair(1) | curses.A_BOLD)

        self.scr.refresh()

    def get_selected_node(self):
        nodes = self.data.get("nodes_list", [])
        if nodes and 0 <= self.selected < len(nodes):
            return nodes[self.selected]
        return None

    def run(self):
        # Start fetch thread
        t = threading.Thread(target=self.fetch_loop, daemon=True)
        t.start()

        # Initial fetch
        d = api_get("/status")
        if d:
            self.data = d

        while self.running:
            self.draw()
            key = self.scr.getch()
            nodes = self.data.get("nodes_list", [])

            if key in (ord('q'), ord('Q')):
                self.running = False

            elif key == curses.KEY_UP:
                self.selected = max(0, self.selected - 1)

            elif key == curses.KEY_DOWN:
                self.selected = min(len(nodes)-1, self.selected + 1)

            elif key in (ord('v'), ord('V')):
                send_command("mine_vrsc", "all")
                self.set_msg("→ mine_vrsc sent to ALL nodes")

            elif key in (ord('x'), ord('X')):
                send_command("mine_xmr", "all")
                self.set_msg("→ mine_xmr sent to ALL nodes")

            elif key in (ord('s'), ord('S')):
                send_command("stop", "all")
                self.set_msg("→ stop sent to ALL nodes")

            elif key in (ord('r'), ord('R')):
                send_command("remove", "all")
                self.set_msg("→ remove sent to ALL nodes")

            elif key in (ord('u'), ord('U')):
                send_command("update", "all")
                self.set_msg("→ update sent to ALL nodes")

            elif key in (ord('w'), ord('W')):
                node = self.get_selected_node()
                if node:
                    send_command("wol", node.get("id","all"))
                    self.set_msg(f"→ Wake-on-LAN sent to {node.get('hostname','?')}")

            elif key in (10, 13):  # Enter — send command to selected node only
                node = self.get_selected_node()
                if node:
                    nid = node.get("id","")
                    send_command("mine_vrsc", nid)
                    self.set_msg(f"→ mine_vrsc sent to {node.get('hostname','?')}")

def main(stdscr):
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default=CC_URL)
    parser.add_argument("--token", default=CC_TOKEN)
    args, _ = parser.parse_known_args()
    global CC_URL, CC_TOKEN
    CC_URL = args.url
    CC_TOKEN = args.token
    db = Dashboard(stdscr)
    db.run()

if __name__ == "__main__":
    curses.wrapper(main)
