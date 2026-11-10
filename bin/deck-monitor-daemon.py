#!/usr/bin/env python3
import os
import sys
import time
import json
import shutil
import threading
import subprocess
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import socket
import struct

CACHE_DATA = {}
LOCK = threading.Lock()

# Preferences shared by every widget instance (each Plasma widget has its own config,
# but e.g. "show on external monitors" must also reach a widget that is currently hidden).
PREFS_PATH = os.path.expanduser('~/.config/deck-monitor/prefs.json')
PREFS_SCHEMA = {'external_mode': (0, 1, 2)}   # 0 = hide while Deck screen on, 1 = always show, 2 = never show

def load_prefs():
    try:
        with open(PREFS_PATH) as f:
            data = json.load(f)
        return {k: v for k, v in data.items() if k in PREFS_SCHEMA and v in PREFS_SCHEMA[k]}
    except Exception:
        return {}

PREFS = load_prefs()

def save_prefs(update):
    clean = {k: v for k, v in update.items() if k in PREFS_SCHEMA and v in PREFS_SCHEMA[k]}
    if not clean:
        return False
    with LOCK:
        PREFS.update(clean)
        snapshot = dict(PREFS)
    os.makedirs(os.path.dirname(PREFS_PATH), exist_ok=True)
    tmp = PREFS_PATH + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(snapshot, f)
    os.replace(tmp, PREFS_PATH)
    return True

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
                                    'device': real_src,
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

    @staticmethod
    def _running(words):
        """Same match as `pgrep -f <word>` for several words, in one pass over /proc (no subprocesses)."""
        found = set()
        me = str(os.getpid())
        for pid in os.listdir('/proc'):
            if not pid.isdigit() or pid == me:
                continue
            try:
                with open(f'/proc/{pid}/cmdline', 'rb') as f:
                    cmd = f.read().replace(b'\0', b' ')
            except OSError:
                continue
            for w in words:
                if w in cmd:
                    found.add(w)
            if len(found) == len(words):
                break
        return found

    @staticmethod
    def _tmux_sessions():
        # Skip spawning tmux entirely when no tmux server socket exists
        sock_dir = os.path.join(os.environ.get('TMUX_TMPDIR', '/tmp'), f'tmux-{os.getuid()}')
        try:
            if not any(os.path.exists(os.path.join(sock_dir, n)) for n in os.listdir(sock_dir)):
                return 0
        except OSError:
            return 0
        try:
            res = subprocess.run(['tmux', 'ls'], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=1.0, text=True)
            if res.returncode == 0 and res.stdout:
                return len([l for l in res.stdout.strip().splitlines() if l.strip()])
        except Exception:
            pass
        return 0

    def get_services(self):
        running = self._running((b'syncthing', b'dropbox', b'rclone'))
        syncthing = b'syncthing' in running
        dropbox = b'dropbox' in running
        rclone = b'rclone' in running
        tmux_count = self._tmux_sessions()

        tailscale = self._check_tailscale()

        return {
            'syncthing': syncthing,
            'dropbox': dropbox,
            'rclone': rclone,
            'tmux_sessions': tmux_count,
            'tailscale': tailscale
        }

    _ping_seq = 0

    @staticmethod
    def _icmp_checksum(data):
        if len(data) % 2:
            data += b'\0'
        total = sum(struct.unpack(f'!{len(data) // 2}H', data))
        total = (total >> 16) + (total & 0xFFFF)
        total += total >> 16
        return ~total & 0xFFFF

    def _icmp_ping(self, host, timeout=2.0):
        """Echo request over an unprivileged ICMP datagram socket. Returns ms or None."""
        MetricCollector._ping_seq = (MetricCollector._ping_seq + 1) & 0xFFFF
        seq = MetricCollector._ping_seq
        payload = b'deck-monitor'
        header = struct.pack('!BBHHH', 8, 0, 0, 0, seq)
        packet = struct.pack('!BBHHH', 8, 0, self._icmp_checksum(header + payload), 0, seq) + payload
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_ICMP) as s:
            start = time.monotonic()
            deadline = start + timeout
            s.sendto(packet, (host, 0))
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return None
                s.settimeout(remaining)
                try:
                    data, _ = s.recvfrom(1024)
                except socket.timeout:
                    return None
                if len(data) >= 8 and data[0] == 0 and struct.unpack('!H', data[6:8])[0] == seq:
                    return (time.monotonic() - start) * 1000.0

    def get_ping(self):
        for target in ['1.1.1.1', '8.8.8.8']:
            try:
                ms = self._icmp_ping(target)
                if ms is not None:
                    return f"{round(ms, 1)} ms"
            except PermissionError:
                return self._ping_subprocess()
            except OSError:
                pass
        return "Offline"

    def _ping_subprocess(self):
        for target in ['1.1.1.1', '8.8.8.8']:
            try:
                res = subprocess.run(['ping', '-c', '1', '-W', '2', target], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=2.5, text=True)
                if res.returncode == 0 and res.stdout:
                    for line in res.stdout.splitlines():
                        if 'time=' in line:
                            val = line.split('time=')[1].split()[0]
                            return f"{round(float(val), 1)} ms"
            except Exception:
                pass
        return "Offline"

    def collect_fast(self):
        # Cheap /proc + /sys reads: refreshed every cycle
        return {
            'timestamp': int(time.time()),
            'cpu_percent': self.get_cpu(),
            'memory': self.get_memory(),
            'storage': self.get_storage(),
            'sdcard': self.get_sdcard(),
            'external_drives': self.get_external_drives(),
            'battery': self.get_battery(),
            'temp': self.get_temperature(),
        }

    def collect_slow(self):
        # Spawns nmcli / talks to tailscaled: these change rarely
        return {
            'wifi': self.get_wifi(),
            'services': self.get_services(),
        }

    def collect_all(self):
        return dict(self.collect_fast(), **self.collect_slow(), ping=self.get_ping())

def parent_disk(dev):
    """/dev/sda1 -> /dev/sda, /dev/nvme1n1p2 -> /dev/nvme1n1 (via sysfs)."""
    name = os.path.basename(dev)
    sys_path = f'/sys/class/block/{name}'
    if os.path.exists(os.path.join(sys_path, 'partition')):
        return '/dev/' + os.path.basename(os.path.dirname(os.path.realpath(sys_path)))
    return dev

def eject_mount(mount):
    """Unmount one external partition; power the drive off once none of its partitions are mounted."""
    drive = next((d for d in MetricCollector().get_external_drives() if d['mount'] == mount), None)
    if not drive:
        return 404, {'ok': False, 'error': 'Not an external drive'}
    dev = drive['device']
    res = subprocess.run(['udisksctl', 'unmount', '-b', dev, '--no-user-interaction'],
                         capture_output=True, text=True, timeout=60)
    if res.returncode != 0:
        err = (res.stderr or res.stdout).strip()
        if 'busy' in err.lower():
            err = 'Drive busy, close apps using it'
        return 409, {'ok': False, 'error': err.splitlines()[-1] if err else 'Unmount failed'}

    disk = parent_disk(dev)
    still_mounted = False
    try:
        with open('/proc/mounts') as f:
            for line in f:
                src = os.path.realpath(line.split()[0])
                if src.startswith('/dev/') and parent_disk(src) == disk:
                    still_mounted = True
                    break
    except Exception:
        still_mounted = True
    powered_off = False
    if not still_mounted:
        po = subprocess.run(['udisksctl', 'power-off', '-b', disk, '--no-user-interaction'],
                            capture_output=True, text=True, timeout=30)
        powered_off = po.returncode == 0
    return 200, {'ok': True, 'powered_off': powered_off,
                 'message': 'Safe to remove' if powered_off or not still_mounted else 'Unmounted'}

FAST_INTERVAL = 2.0     # cpu / memory / battery / temp / drives
SLOW_INTERVAL = 10.0    # wifi + services
PING_INTERVAL = 2.0
IDLE_AFTER = 20.0       # stop sampling when nobody has asked for /status this long
STALE_AFTER = 5.0       # a /status request older data than this waits briefly for a fresh sample

LAST_STATUS_REQUEST = 0.0
WAKE = threading.Event()
FRESH = threading.Condition(LOCK)

def is_active():
    return time.time() - LAST_STATUS_REQUEST < IDLE_AFTER

def update_loop():
    global CACHE_DATA
    collector = MetricCollector()
    slow = {}
    last_slow = 0.0
    was_idle = True
    while True:
        if not is_active():
            was_idle = True
            WAKE.wait()            # sleep until a client asks for /status
            WAKE.clear()
            continue
        if was_idle:
            # CPU% is a delta: re-baseline so the first sample isn't an average over the idle gap
            collector._init_cpu()
            time.sleep(0.5)
            was_idle = False
            last_slow = 0.0
        data = collector.collect_fast()
        now = time.monotonic()
        if now - last_slow >= SLOW_INTERVAL:
            slow = collector.collect_slow()
            last_slow = now
        data.update(slow)
        with FRESH:
            data['ping'] = CACHE_DATA.get('ping', '...')
            CACHE_DATA = data
            FRESH.notify_all()
        WAKE.wait(FAST_INTERVAL)
        WAKE.clear()

def ping_loop():
    collector = MetricCollector()
    while True:
        if is_active():
            value = collector.get_ping()
            with LOCK:
                CACHE_DATA['ping'] = value
        time.sleep(PING_INTERVAL)

def get_status():
    """Return the cached sample, waking the collector (and waiting up to 3s) if it is idle or stale."""
    global LAST_STATUS_REQUEST
    LAST_STATUS_REQUEST = time.time()
    with FRESH:
        if time.time() - CACHE_DATA.get('timestamp', 0) > STALE_AFTER:
            WAKE.set()
            FRESH.wait_for(lambda: time.time() - CACHE_DATA.get('timestamp', 0) <= STALE_AFTER, timeout=3.0)
        return dict(CACHE_DATA, prefs=dict(PREFS))

class RequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ('/status', '/', '/api', '/prefs'):
            if self.path == '/prefs':
                # cheap endpoint for hidden widgets; does not keep the collector awake
                with LOCK:
                    body = json.dumps({'prefs': dict(PREFS)}).encode('utf-8')
            else:
                body = json.dumps(get_status()).encode('utf-8')
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

    def do_POST(self):
        if self.path not in ('/eject', '/prefs'):
            self.send_response(404)
            self.end_headers()
            return
        try:
            length = int(self.headers.get('Content-Length', 0))
            req = json.loads(self.rfile.read(length) or b'{}')
            if self.path == '/prefs':
                ok = save_prefs(req)
                code, payload = (200 if ok else 400), {'ok': ok, 'prefs': dict(PREFS)}
            else:
                code, payload = eject_mount(req.get('mount', ''))
        except Exception as e:
            code, payload = 500, {'ok': False, 'error': str(e)}
        body = json.dumps(payload).encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass

class ReusableHTTPServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    def server_bind(self):
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        except (AttributeError, OSError):
            pass
        super().server_bind()

def main():
    threading.Thread(target=update_loop, daemon=True).start()
    threading.Thread(target=ping_loop, daemon=True).start()
    
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
