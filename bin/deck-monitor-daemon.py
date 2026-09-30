#!/usr/bin/env python3
import os
import sys
import time
import json
import shutil
import threading
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler

CACHE_DATA = {}
LOCK = threading.Lock()

class MetricCollector:
    def __init__(self):
        self.prev_idle = 0.0
        self.prev_total = 0.0
        self._init_cpu()

    def _init_cpu(self):
        try:
            with open('/proc/stat', 'r') as f:
                fields = [float(x) for x in f.readline().strip().split()[1:]]
            self.prev_idle = fields[3] + fields[4]
            self.prev_total = sum(fields)
        except Exception:
            pass

    def get_cpu(self):
        try:
            with open('/proc/stat', 'r') as f:
                fields = [float(x) for x in f.readline().strip().split()[1:]]
            idle = fields[3] + fields[4]
            total = sum(fields)
            idle_delta = idle - self.prev_idle
            total_delta = total - self.prev_total
            self.prev_idle = idle
            self.prev_total = total
            if total_delta > 0:
                usage = 100.0 * (1.0 - (idle_delta / total_delta))
                return max(0.0, min(100.0, round(usage, 1)))
        except Exception:
            pass
        return 0.0

    def get_memory(self):
        try:
            mem = {}
            with open('/proc/meminfo', 'r') as f:
                for line in f:
                    parts = line.split(':')
                    if len(parts) == 2:
                        mem[parts[0].strip()] = int(parts[1].strip().split()[0])
            total = mem.get('MemTotal', 1)
            avail = mem.get('MemAvailable', 0)
            used = total - avail
            pct = round((used / total) * 100.0, 1)
            return {
                'percent': pct,
                'used_gb': round(used / (1024 * 1024), 1),
                'total_gb': round(total / (1024 * 1024), 1)
            }
        except Exception:
            return {'percent': 0.0, 'used_gb': 0.0, 'total_gb': 0.0}

    def get_storage(self):
        try:
            total, used, free = shutil.disk_usage('/home')
            pct = round((used / total) * 100.0, 1)
            return {
                'percent': pct,
                'used_gb': round(used / (1024**3), 1),
                'total_gb': round(total / (1024**3), 1),
                'free_gb': round(free / (1024**3), 1)
            }
        except Exception:
            return {'percent': 0.0, 'used_gb': 0.0, 'total_gb': 0.0, 'free_gb': 0.0}

    def get_battery(self):
        pct = 0
        status = 'Unknown'
        health = 'N/A'
        try:
            b_path = '/sys/class/power_supply/BAT1'
            if not os.path.exists(b_path):
                b_path = '/sys/class/power_supply/BAT0'
            if os.path.exists(b_path):
                if os.path.exists(f'{b_path}/capacity'):
                    with open(f'{b_path}/capacity') as f:
                        pct = int(f.read().strip())
                if os.path.exists(f'{b_path}/status'):
                    with open(f'{b_path}/status') as f:
                        status = f.read().strip()
                cf = 0
                cfd = 0
                if os.path.exists(f'{b_path}/charge_full'):
                    with open(f'{b_path}/charge_full') as f:
                        cf = int(f.read().strip())
                elif os.path.exists(f'{b_path}/energy_full'):
                    with open(f'{b_path}/energy_full') as f:
                        cf = int(f.read().strip())

                if os.path.exists(f'{b_path}/charge_full_design'):
                    with open(f'{b_path}/charge_full_design') as f:
                        cfd = int(f.read().strip())
                elif os.path.exists(f'{b_path}/energy_full_design'):
                    with open(f'{b_path}/energy_full_design') as f:
                        cfd = int(f.read().strip())

                if cfd > 0 and cf > 0:
                    health = f"{round((cf / cfd) * 100, 1)}%"
        except Exception:
            pass
        return {'percent': pct, 'status': status, 'health': health}

    def get_temperature(self):
        try:
            temps = []
            for hw in os.listdir('/sys/class/hwmon'):
                name_p = f'/sys/class/hwmon/{hw}/name'
                if os.path.exists(name_p):
                    with open(name_p) as f:
                        name = f.read().strip()
                    if name in ('amdgpu', 'acpitz'):
                        for f in os.listdir(f'/sys/class/hwmon/{hw}'):
                            if f.endswith('_input') and 'temp' in f:
                                try:
                                    with open(f'/sys/class/hwmon/{hw}/{f}') as tf:
                                        val = int(tf.read().strip()) / 1000.0
                                        if 10 < val < 115:
                                            temps.append(val)
                                except Exception:
                                    pass
            if temps:
                return f"{round(max(temps), 0):.0f}°C"
        except Exception:
            pass
        return "N/A"

    def get_services(self):
        syncthing = subprocess.call(['pgrep', '-x', 'syncthing'], stdout=subprocess.DEVNULL) == 0
        dropbox = subprocess.call(['pgrep', '-f', 'dropbox'], stdout=subprocess.DEVNULL) == 0
        rclone = subprocess.call(['pgrep', '-x', 'rclone'], stdout=subprocess.DEVNULL) == 0
        
        tmux_count = 0
        try:
            out = subprocess.check_output(['tmux', 'ls'], stderr=subprocess.DEVNULL).decode()
            tmux_count = len([l for l in out.strip().splitlines() if l.strip()])
        except Exception:
            tmux_count = 0

        tailscale = False
        try:
            res = subprocess.call(['tailscale', 'status'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            tailscale = (res == 0)
        except Exception:
            tailscale = False

        return {
            'syncthing': syncthing,
            'dropbox': dropbox,
            'rclone': rclone,
            'tmux_sessions': tmux_count,
            'tailscale': tailscale
        }

    def get_ping(self):
        try:
            out = subprocess.check_output(['ping', '-c', '1', '-W', '1', '1.1.1.1'], stderr=subprocess.DEVNULL).decode()
            for line in out.splitlines():
                if 'time=' in line:
                    val = line.split('time=')[1].split()[0]
                    return f"{round(float(val), 1)} ms"
        except Exception:
            pass
        return "Offline"

    def collect_all(self):
        return {
            'timestamp': int(time.time()),
            'cpu_percent': self.get_cpu(),
            'memory': self.get_memory(),
            'storage': self.get_storage(),
            'battery': self.get_battery(),
            'temp': self.get_temperature(),
            'services': self.get_services(),
            'ping': self.get_ping()
        }

def update_loop():
    global CACHE_DATA
    collector = MetricCollector()
    while True:
        data = collector.collect_all()
        with LOCK:
            CACHE_DATA = data
        time.sleep(2.0)

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ('/status', '/', '/api'):
            with LOCK:
                body = json.dumps(CACHE_DATA).encode('utf-8')
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass

class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True
    def server_bind(self):
        import socket
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        except (AttributeError, OSError):
            pass
        super().server_bind()

def main():
    t = threading.Thread(target=update_loop, daemon=True)
    t.start()
    
    server_address = ('127.0.0.1', 19842)
    httpd = ReusableHTTPServer(server_address, RequestHandler)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()

if __name__ == '__main__':
    main()
