#!/usr/bin/env python3
import os
import sys
import time
import json
import shutil
import threading
import subprocess
from http.server import HTTPServer, BaseHTTPRequestHandler
import socket

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

    def get_sdcard(self):
        sd_path = '/run/media/deck/SDcard'
        if not (os.path.exists(sd_path) and os.path.ismount(sd_path)):
            sd_path = None
            try:
                with open('/proc/mounts', 'r') as f:
                    for line in f:
                        parts = line.strip().split()
                        if len(parts) >= 2 and parts[0].startswith('/dev/mmcblk0'):
                            sd_path = parts[1].replace('\\040', ' ')
                            break
            except Exception:
                pass

        if sd_path and os.path.exists(sd_path) and os.path.ismount(sd_path):
            try:
                total, used, free = shutil.disk_usage(sd_path)
                pct = round((used / total) * 100.0, 1)
                return {
                    'mounted': True,
                    'mount': sd_path,
                    'percent': pct,
                    'used_gb': round(used / (1024**3), 1),
                    'total_gb': round(total / (1024**3), 1),
                    'free_gb': round(free / (1024**3), 1)
                }
            except Exception:
                pass
        return {
            'mounted': False,
            'percent': 0.0,
            'used_gb': 0.0,
            'total_gb': 0.0,
            'free_gb': 0.0
        }

    def get_external_drives(self):
        drives = []
        seen_mounts = set()
        labels = {}
        if os.path.exists('/dev/disk/by-label'):
            try:
                for lbl in os.listdir('/dev/disk/by-label'):
                    full_p = os.path.join('/dev/disk/by-label', lbl)
                    if os.path.islink(full_p):
                        real_p = os.path.realpath(full_p)
                        labels[real_p] = lbl.replace('\\x20', ' ')
            except Exception:
                pass

        try:
            with open('/proc/mounts', 'r') as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) < 3:
                        continue
                    src = parts[0].replace('\\040', ' ')
                    target = parts[1].replace('\\040', ' ')
                    fstype = parts[2]

                    if fstype in ('tmpfs', 'devtmpfs', 'proc', 'sysfs', 'fuse.rclone', 'portal',
                                  'cgroup', 'cgroup2', 'overlay', 'autofs', 'fusectl', 'securityfs',
                                  'pstore', 'bpf', 'tracefs', 'debugfs', 'hugetlbfs', 'mqueue', 'devpts'):
                        continue

                    if src.startswith('/dev/nvme0n1') or src.startswith('/dev/mmcblk0') or src.startswith('/dev/zram') or src == 'none':
                        continue

                    if target in ('/', '/home', '/var', '/opt', '/root', '/srv', '/nix', '/efi', '/esp') or target.startswith('/run/media/deck/SDcard'):
                        continue

                    is_ext = False
                    if src.startswith('/dev/sd') or (src.startswith('/dev/nvme') and not src.startswith('/dev/nvme0n1')):
                        is_ext = True
                    elif target.startswith('/run/media/') or target.startswith('/media/'):
                        is_ext = True

                    if is_ext and target not in seen_mounts and os.path.exists(target) and os.path.ismount(target):
                        seen_mounts.add(target)
                        try:
                            total, used, free = shutil.disk_usage(target)
                            if total > 0:
                                pct = round((used / total) * 100.0, 1)
                                real_src = os.path.realpath(src)
                                drive_name = labels.get(real_src) or os.path.basename(target.rstrip('/'))
                                if not drive_name or drive_name in ('deck', 'media'):
                                    drive_name = 'External'
                                drives.append({
                                    'name': drive_name,
                                    'mount': target,
                                    'percent': pct,
                                    'used_gb': round(used / (1024**3), 1),
                                    'total_gb': round(total / (1024**3), 1),
                                    'free_gb': round(free / (1024**3), 1)
                                })
                        except Exception:
                            pass
        except Exception:
            pass
        return drives

    def get_battery(self):
        pct = 0
        status = 'Discharging'
        health = 'N/A'
        acad = 0
        try:
            if os.path.exists('/sys/class/power_supply/ACAD/online'):
                with open('/sys/class/power_supply/ACAD/online') as f:
                    acad = int(f.read().strip())
        except Exception:
            pass

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

        is_plugged = (acad == 1)
        is_charging = (status == 'Charging')
        if is_charging:
            charge_label = 'Charging'
        elif is_plugged:
            charge_label = 'Plugged In'
        else:
            charge_label = 'Discharging'

        return {
            'percent': pct,
            'status': status,
            'health': health,
            'is_plugged': is_plugged,
            'is_charging': is_charging,
            'charge_label': charge_label
        }

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

    def get_wifi(self):
        try:
            res = subprocess.run(['nmcli', '-t', '-f', 'DEVICE,TYPE,NAME', 'c', 'show', '--active'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=1.5, text=True)
            if res.returncode == 0 and res.stdout:
                for line in res.stdout.splitlines():
                    parts = line.strip().split(':')
                    if len(parts) >= 3:
                        dev, conn_type, conn_name = parts[0], parts[1], parts[2]
                        if conn_type in ('802-11-wireless', 'wifi', 'ethernet', 'bluetooth', 'gsm', 'cdma'):
                            is_tethering = False
                            if conn_type in ('bluetooth', 'gsm', 'cdma') or 'usb' in dev.lower() or 'rndis' in dev.lower():
                                is_tethering = True
                            else:
                                name_lower = conn_name.lower()
                                keywords = ['hotspot', 'tether', 'iphone', 'android', 'galaxy', 'pixel', 'redmi', 'xiaomi', 'poco', 'oppo', 'vivo', 'realme']
                                if any(kw in name_lower for kw in keywords):
                                    is_tethering = True
                                else:
                                    try:
                                        m_res = subprocess.run(['nmcli', '-t', '-f', 'GENERAL.METERED', 'dev', 'show', dev], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=1.0, text=True)
                                        if m_res.returncode == 0 and m_res.stdout and 'yes' in m_res.stdout.lower():
                                            is_tethering = True
                                    except Exception:
                                        pass
                            return {
                                'name': conn_name,
                                'is_tethering': is_tethering,
                                'icon': 'network-wireless-hotspot-symbolic' if is_tethering else 'network-wireless-symbolic',
                                'connected': True
                            }
        except Exception:
            pass
        return {
            'name': 'Disconnected',
            'is_tethering': False,
            'icon': 'network-wireless-disconnected-symbolic',
            'connected': False
        }

    def _check_tailscale(self):
        # Layer 1: Direct UNIX socket query to tailscaled daemon (fastest: ~1ms, 0 subprocesses spawned)
        sock_path = '/run/tailscale/tailscaled.sock'
        if os.path.exists(sock_path):
            try:
                s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                s.settimeout(0.5)
                s.connect(sock_path)
                s.sendall(b'GET /localapi/v0/status HTTP/1.0\r\nHost: local-tailscaled.sock\r\n\r\n')
                resp = b''
                while True:
                    chunk = s.recv(4096)
                    if not chunk:
                        break
                    resp += chunk
                s.close()
                parts = resp.split(b'\r\n\r\n', 1)
                if len(parts) == 2:
                    data = json.loads(parts[1].decode('utf-8', errors='ignore'))
                    return data.get('BackendState') == 'Running'
            except Exception:
                pass

        # Layer 2: tailscale status CLI command with multi-path discovery
        candidates = [shutil.which('tailscale'), '/opt/tailscale/tailscale', '/home/deck/.local/bin/tailscale', '/usr/bin/tailscale']
        for cand in candidates:
            if cand and os.path.exists(cand):
                try:
                    res = subprocess.run([cand, 'status'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=1.5)
                    if res.returncode == 0:
                        return True
                except Exception:
                    pass
                break

        # Layer 3: Kernel network interface check (sysfs)
        carrier_path = '/sys/class/net/tailscale0/carrier'
        if os.path.exists(carrier_path):
            try:
                with open(carrier_path, 'r') as f:
                    return f.read().strip() == '1'
            except Exception:
                pass

        return False

    def get_services(self):
        syncthing = False
        try:
            syncthing = subprocess.run(['pgrep', '-f', 'syncthing'], stdout=subprocess.DEVNULL, timeout=1.0).returncode == 0
        except Exception:
            pass

        dropbox = False
        try:
            dropbox = subprocess.run(['pgrep', '-f', 'dropbox'], stdout=subprocess.DEVNULL, timeout=1.0).returncode == 0
        except Exception:
            pass

        rclone = False
        try:
            rclone = subprocess.run(['pgrep', '-f', 'rclone'], stdout=subprocess.DEVNULL, timeout=1.0).returncode == 0
        except Exception:
            pass

        tmux_count = 0
        try:
            res = subprocess.run(['tmux', 'ls'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=1.0, text=True)
            if res.returncode == 0 and res.stdout:
                tmux_count = len([l for l in res.stdout.strip().splitlines() if l.strip()])
        except Exception:
            tmux_count = 0

        tailscale = self._check_tailscale()

        return {
            'syncthing': syncthing,
            'dropbox': dropbox,
            'rclone': rclone,
            'tmux_sessions': tmux_count,
            'tailscale': tailscale
        }

    def get_ping(self):
        for target in ['1.1.1.1', '8.8.8.8']:
            try:
                res = subprocess.run(['ping', '-c', '1', '-W', '1', target], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=1.5, text=True)
                if res.returncode == 0 and res.stdout:
                    for line in res.stdout.splitlines():
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
            'sdcard': self.get_sdcard(),
            'external_drives': self.get_external_drives(),
            'battery': self.get_battery(),
            'temp': self.get_temperature(),
            'wifi': self.get_wifi(),
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
